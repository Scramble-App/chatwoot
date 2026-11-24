# Passes a conversation from the AI agent to the team: sets the handoff team first, so assignment considers it, labels the
# conversation, leaves a private note for the team and opens the conversation through bot_handoff!. When the knowledge
# base had no answer, record_unanswered_question then records the question, after the reply is posted.
class AiAgents::HandoffService
  LABEL = 'ai-handoff'.freeze
  NOTE_QUESTION_LIMIT = 1_000

  # reason: no_answer, human_requested or other from the model, or limit, error or ungrounded from the reply service.
  # message: the visitor message being answered; language: of the agent's reply, if there was one.
  pattr_initialize [:agent_bot!, :message!, :reason!, { summary: nil, unanswered_question: nil, visitor_question: nil, language: nil }]

  # False, changing nothing, when an agent took the conversation over or it was closed in the meantime
  def perform
    # save_contact can have moved the conversation to another contact
    conversation.reload
    return false unless conversation.pending? && conversation.assignee_id.nil?

    label_title = label.title
    # All or nothing: a half-done handoff can leave the conversation pending with the team, the note or an assignee, where
    # the AI agent never replies again and nobody is told
    ActiveRecord::Base.transaction do
      assign_team
      conversation.add_labels([label_title])
      create_note
      conversation.bot_handoff!
    end
    true
  end

  def record_unanswered_question
    return unless reason == 'no_answer'

    question = unanswered_question.presence || message.content.to_s.squish.presence
    return if question.blank?

    AiAgents::UnansweredRecorder.new(agent_bot: agent_bot, conversation: conversation, message: message, question: question,
                                     visitor_question: visitor_question).perform
  end

  private

  def conversation
    @conversation ||= message.conversation
  end

  def assign_team
    team = agent_bot.ai_agent_settings.handoff_team
    conversation.update!(team: team) if team && conversation.team_id != team.id
  end

  # Two handoffs in the account can try to create the label at once; the savepoint keeps a caller's transaction usable
  def label
    labels = conversation.account.labels
    labels.find_by(title: LABEL) ||
      Label.transaction(requires_new: true) { labels.create!(title: LABEL, description: I18n.t('ai_agents.handoff.label_description')) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    labels.find_by!(title: LABEL)
  end

  def create_note
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: agent_bot,
      content: note
    )
  end

  def note
    facts = { reason: I18n.t("ai_agents.handoff.reasons.#{reason}"), question: note_question, company: company, email: conversation.contact.email }
    facts[:given_email] = given_email if given_email.present?
    facts[:language] = language
    lines = facts.map { |name, value| I18n.t("ai_agents.handoff.note.#{name}", name => value.presence || I18n.t('ai_agents.handoff.unknown')) }
    lines << I18n.t('ai_agents.handoff.note.summary', summary: summary) if summary.present?
    [I18n.t('ai_agents.handoff.note.title'), *lines].join("\n")
  end

  # The company the visitor gave in this conversation comes first: an email can have merged them into another contact
  def company
    conversation.additional_attributes&.dig(AiAgents::ConversationContext::VISITOR_DETAILS, 'company').presence ||
      conversation.contact.additional_attributes&.dig('company_name')
  end

  # An email the visitor gave that their contact didn't take, as it had one
  def given_email
    email = conversation.additional_attributes&.dig(AiAgents::ConversationContext::VISITOR_EMAIL)
    email unless email == conversation.contact.email
  end

  # The English question the model couldn't answer, otherwise what the visitor wrote last
  def note_question
    question = unanswered_question if reason == 'no_answer'
    (question.presence || message.content).to_s.squish.truncate(NOTE_QUESTION_LIMIT)
  end
end
