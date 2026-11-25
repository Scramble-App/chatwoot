# Passes a conversation from the AI agent to the team: leaves a private note for the team and, in one save, sets the
# handoff team (so assignment considers it) or, when the conversation has it already, one of its agents, the label and
# what bot_handoff! sets (waiting_since, status open). The caller sends bot_handoff!'s event with dispatch_event once
# everything is committed and, when the knowledge base had no answer, records the question with record_unanswered_question.
class AiAgents::HandoffService
  LABEL = 'ai-handoff'.freeze
  NOTE_QUESTION_LIMIT = 1_000

  # reason: no_answer, human_requested or other from the model, or limit, hourly_limit, error or ungrounded from the reply
  # service.
  # message: the visitor message being answered; language: of the agent's reply, if there was one.
  pattr_initialize [:agent_bot!, :message!, :reason!, { summary: nil, unanswered_question: nil, visitor_question: nil, language: nil }]

  # False, changing nothing, when an agent took the conversation over or it was closed in the meantime
  def perform
    # save_contact can have moved the conversation to another contact
    conversation.reload
    return false unless conversation.pending? && conversation.assignee_id.nil?

    # All or nothing: a half-done handoff can leave the conversation pending with the team, the note or an assignee, where
    # the AI agent never replies again and nobody is told. One save of the conversation, as its after_commit callbacks (team
    # and assignee events, assignment history) run once per transaction and see only the last save's changes.
    ActiveRecord::Base.transaction do
      create_note
      conversation.update!(handoff_changes)
    end
    true
  end

  # bot_handoff!'s event (Reports → Bot, notifications) as bot_handoff! sends it, but only once the handoff is committed: a
  # handoff that rolls back sends none, and listeners find the conversation open
  def dispatch_event
    Rails.configuration.dispatcher.dispatch(Events::Types::CONVERSATION_BOT_HANDOFF, Time.zone.now,
                                            conversation: conversation, notifiable_assignee_change: conversation.notifiable_assignee_change?,
                                            changed_attributes: nil, performed_by: Current.executed_by)
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

  # What bot_handoff! sets (waiting_since when blank, status open), with the label and the handoff team
  def handoff_changes
    changes = { label_list: conversation.label_list | [label.title], status: :open }
    changes[:waiting_since] = Time.current if conversation.waiting_since.blank?
    changes.merge(team_changes)
  end

  # Setting the team assigns one of its agents (AssignmentHandler). A conversation that has the team already, as when the
  # visitor wrote again after the team resolved it, gets one the same way.
  def team_changes
    team = agent_bot.ai_agent_settings.handoff_team
    return {} unless team
    return { team: team } if conversation.team_id != team.id

    { assignee: team_assignee(team) }.compact
  end

  # An online team member with capacity, as AssignmentHandler picks one when the team changes, if the team auto assigns
  def team_assignee(team)
    return unless team.allow_auto_assign

    agent_ids = conversation.inbox.member_ids_with_assignment_capacity & team.members.ids
    AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: agent_ids).find_assignee
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
