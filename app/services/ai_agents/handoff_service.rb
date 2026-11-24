# Passes a conversation from the AI agent to the team: sets the handoff team first, so assignment considers it, labels the
# conversation, leaves a private note for the team, opens the conversation through bot_handoff! and, when the knowledge
# base had no answer, records the unanswered question.
class AiAgents::HandoffService
  LABEL = 'ai-handoff'.freeze
  NOTE_QUESTION_LIMIT = 1_000

  # reason: no_answer, human_requested or other from the model, or limit, error or ungrounded from the reply service.
  # message: the visitor message being answered; language: of the agent's reply, if there was one.
  pattr_initialize [:agent_bot!, :message!, :reason!, { summary: nil, unanswered_question: nil, language: nil }]

  def perform
    # The reply that came before can have changed the conversation (waiting_since) and save_contact its contact
    conversation.reload
    assign_team
    conversation.add_labels([label.title])
    create_note
    conversation.bot_handoff!
    record_unanswered_question if reason == 'no_answer'
  end

  private

  def conversation
    @conversation ||= message.conversation
  end

  def assign_team
    team = agent_bot.ai_agent_settings.handoff_team
    conversation.update!(team: team) if team && conversation.team_id != team.id
  end

  # Two handoffs in the account can try to create the label at once
  def label
    labels = conversation.account.labels
    labels.find_by(title: LABEL) || labels.create!(title: LABEL, description: I18n.t('ai_agents.handoff.label_description'))
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
    contact = conversation.contact
    facts = {
      reason: I18n.t("ai_agents.handoff.reasons.#{reason}"),
      question: note_question,
      company: contact.additional_attributes&.dig('company_name'),
      email: contact.email,
      language: language
    }
    lines = facts.map { |name, value| I18n.t("ai_agents.handoff.note.#{name}", name => value.presence || I18n.t('ai_agents.handoff.unknown')) }
    lines << I18n.t('ai_agents.handoff.note.summary', summary: summary) if summary.present?
    [I18n.t('ai_agents.handoff.note.title'), *lines].join("\n")
  end

  # The English question the model couldn't answer, otherwise what the visitor wrote last
  def note_question
    question = unanswered_question if reason == 'no_answer'
    (question.presence || message.content).to_s.squish.truncate(NOTE_QUESTION_LIMIT)
  end

  def record_unanswered_question
    question = unanswered_question.presence || message.content.to_s.squish.presence
    return if question.blank?

    AiAgents::UnansweredRecorder.new(agent_bot: agent_bot, conversation: conversation, message: message, question: question).perform
  end
end
