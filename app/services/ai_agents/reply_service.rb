# Replies to a visitor message as an AI agent bot. The Responder decides the reply with the real tools: save_contact saves
# the contact at once, and a hand_off request is carried out once the reply is decided.
#
# The model call takes a while, so the reply conditions are checked again after it: when the visitor wrote again or an
# agent took over, the reply and its handoff are dropped, and the job of the newer message answers with the whole
# history. A handoff comes before its reply, which keeps the waiting time the handoff started (preserve_waiting_since),
# so a handoff that fails fails the job before anything is posted and the job's retry completes it.
#
# The reply limit, an OpenAI error and a reply that isn't grounded post the fallback message and hand off.
class AiAgents::ReplyService
  include Events::Types

  # message: the latest incoming message of the conversation
  pattr_initialize [:agent_bot!, :message!]

  def perform
    return hand_off_with(settings.fallback_message, reason: 'limit') if reply_limit_reached?

    result = with_typing { responder.perform }
    reply_with(result) if still_replyable?
  rescue AiAgents::Responder::Error => e
    Rails.logger.warn("[ai-agent] conversation=#{conversation.id} agent_bot=#{agent_bot.id} reply failed: #{e.message}")
    hand_off_with(settings.fallback_message, reason: 'error') if still_replyable?
  ensure
    log_usage
  end

  private

  def conversation
    @conversation ||= message.conversation
  end

  def settings
    @settings ||= agent_bot.ai_agent_settings
  end

  def context
    @context ||= AiAgents::ConversationContext.new(conversation: conversation, message: message, team: settings.handoff_team)
  end

  def team_available?
    @team_available = context.team_available? if @team_available.nil?
    @team_available
  end

  def responder
    @responder ||= AiAgents::Responder.new(
      agent_bot: agent_bot,
      visitor: context.visitor,
      team_available: team_available?,
      history: context.history,
      executor: method(:execute_tool)
    )
  end

  def reply_with(result)
    return hand_off_with(settings.fallback_message, reason: 'ungrounded', language: result.language) unless result.grounded

    # A reply that says it hands off does, also when the model didn't call hand_off
    @handoff_request ||= { 'reason' => 'other' } if result.kind == 'handoff'
    @handoff_request ? hand_off_with(result.reply, language: result.language) : post(result.reply)
  end

  def reply_limit_reached?
    conversation.messages.outgoing.where(private: false, sender: agent_bot).count >= settings.max_replies_per_conversation
  end

  def still_replyable?
    AiAgents::ReplyConditions.new(agent_bot: agent_bot, message: message).met?
  end

  def with_typing
    dispatch_typing(CONVERSATION_TYPING_ON)
    yield
  ensure
    dispatch_typing(CONVERSATION_TYPING_OFF)
  end

  def dispatch_typing(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: conversation, user: agent_bot, is_private: false)
  end

  def execute_tool(name, arguments)
    return save_contact(arguments) if name == 'save_contact'

    @handoff_request = arguments
    { team_available: team_available? }
  end

  # Like the widget's email collection, an email of another contact merges this contact into it, keeping its name. That
  # contact can be another customer, so the prompt gets only the details the visitor gave in this conversation.
  def save_contact(details)
    params = details.slice('name', 'email').symbolize_keys
    if params.present?
      ContactIdentifyAction.new(contact: conversation.contact, params: params, retain_original_contact_name: true, discard_invalid_attrs: true)
                           .perform
      # A merge moves the conversation to the other contact
      conversation.reload
    end
    save_company(details['company']) if details['company']
    remember_visitor_details(details)
    { saved: details.keys }
  rescue ActiveRecord::RecordInvalid => e
    { error: e.record.errors.full_messages.to_sentence }
  end

  # The company of a contact is never replaced: the contact can be an existing customer
  def save_company(company)
    contact = conversation.contact
    attributes = contact.additional_attributes || {}
    contact.update!(additional_attributes: attributes.merge('company_name' => company)) if attributes['company_name'].blank?
  end

  def remember_visitor_details(details)
    attributes = conversation.additional_attributes || {}
    given = (attributes[AiAgents::ConversationContext::VISITOR_DETAILS] || {}).merge(details.slice('name', 'company'))
    conversation.update!(additional_attributes: attributes.merge(AiAgents::ConversationContext::VISITOR_DETAILS => given))
  end

  # The unanswered question is recorded after the reply is posted, so a failure there doesn't cost the visitor the reply
  def hand_off_with(content, reason: nil, language: nil)
    request = @handoff_request || {}
    handoff = AiAgents::HandoffService.new(
      agent_bot: agent_bot, message: message, reason: request['reason'] || reason, summary: request['summary'],
      unanswered_question: request['unanswered_question'], visitor_question: request['visitor_question'], language: language
    )
    return unless handoff.perform

    post(content, preserve_waiting_since: true)
    handoff.record_unanswered_question
  end

  def post(content, preserve_waiting_since: false)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, sender: agent_bot, content: content,
      content_attributes: { ai_agent_reply_to: message.id }, preserve_waiting_since: preserve_waiting_since
    )
  end

  def log_usage
    return unless @responder

    usage = @responder.usage
    Rails.logger.info(
      "[ai-agent] conversation=#{conversation.id} agent_bot=#{agent_bot.id} model=#{@responder.model} requests=#{usage[:requests]} " \
      "input_tokens=#{usage[:input_tokens]} cached_input_tokens=#{usage[:cached_input_tokens]} cache_write_tokens=#{usage[:cache_write_tokens]} " \
      "output_tokens=#{usage[:output_tokens]}"
    )
  end
end
