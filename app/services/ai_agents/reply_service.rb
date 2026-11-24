# Replies to a visitor message as an AI agent bot. The Responder decides the reply with the real tools: save_contact saves
# the contact at once, and a hand_off request is carried out after the reply is posted, so the reply doesn't reset the
# waiting time the handoff starts and the note can name the reply language. The reply limit, an OpenAI error and a
# reply that isn't grounded post the fallback message and hand off.
class AiAgents::ReplyService
  include Events::Types

  # message: the latest incoming message of the conversation
  pattr_initialize [:agent_bot!, :message!]

  def perform
    return fall_back('limit') if reply_limit_reached?

    result = with_typing { responder.perform }
    return fall_back('ungrounded', language: result.language) unless result.grounded

    post(result.reply)
    hand_off(language: result.language) if @handoff_request
  rescue AiAgents::Responder::Error => e
    Rails.logger.warn("[ai-agent] conversation=#{conversation.id} agent_bot=#{agent_bot.id} reply failed: #{e.message}")
    fall_back('error')
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

  def reply_limit_reached?
    conversation.messages.outgoing.where(private: false, sender: agent_bot).count >= settings.max_replies_per_conversation
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

  # Like the widget's email collection, an email of another contact merges this contact into it, keeping its name
  def save_contact(details)
    params = details.slice('name', 'email').symbolize_keys
    params[:additional_attributes] = { company_name: details['company'] } if details['company']
    ContactIdentifyAction.new(contact: conversation.contact, params: params, retain_original_contact_name: true, discard_invalid_attrs: true)
                         .perform
    # A merge moves the conversation to the other contact
    conversation.reload
    { saved: details.keys }
  rescue ActiveRecord::RecordInvalid => e
    { error: e.record.errors.full_messages.to_sentence }
  end

  def fall_back(reason, language: nil)
    post(settings.fallback_message)
    hand_off(reason: reason, language: language)
  end

  # A hand_off the model asked for keeps its reason, also when the fallback message replaced the reply
  def hand_off(reason: nil, language: nil)
    request = @handoff_request || {}
    AiAgents::HandoffService.new(
      agent_bot: agent_bot, message: message, reason: request['reason'] || reason,
      summary: request['summary'], unanswered_question: request['unanswered_question'], language: language
    ).perform
  end

  def post(content)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, sender: agent_bot, content: content
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
