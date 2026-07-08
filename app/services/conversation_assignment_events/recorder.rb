class ConversationAssignmentEvents::Recorder
  def self.record!(conversation:, from_assignee_id:, to_assignee_id:, **)
    new(
      conversation: conversation,
      from_assignee_id: from_assignee_id,
      to_assignee_id: to_assignee_id,
      **
    ).record!
  end

  def initialize(conversation:, from_assignee_id:, to_assignee_id:, **options)
    @conversation = conversation
    @from_assignee_id = from_assignee_id
    @to_assignee_id = to_assignee_id
    @source = options[:source]
    @occurred_at = options.fetch(:occurred_at, Time.current)
    @metadata = options.fetch(:metadata, {})
  end

  def record!
    ConversationAssignmentEvent.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      inbox_id: conversation.inbox_id,
      team_id: conversation.team_id,
      from_assignee_id: from_assignee_id,
      to_assignee_id: to_assignee_id,
      event_type: event_type,
      source: source,
      actor_type: actor&.class&.name,
      actor_id: actor_id,
      occurred_at: occurred_at,
      metadata: metadata || {}
    )
  end

  private

  attr_reader :conversation, :from_assignee_id, :to_assignee_id, :occurred_at, :metadata

  def event_type
    return 'snapshot' if source == 'snapshot'
    return 'assigned' if from_assignee_id.blank? && to_assignee_id.present?
    return 'unassigned' if from_assignee_id.present? && to_assignee_id.blank?

    'reassigned'
  end

  def source
    @source.presence || inferred_source
  end

  def inferred_source
    return Current.assignment_event_source if Current.respond_to?(:assignment_event_source) && Current.assignment_event_source.present?
    return 'automation' if Current.executed_by.is_a?(AutomationRule)
    return 'auto_assignment' if Current.executed_by.is_a?(AssignmentPolicy) || Current.executed_by.is_a?(Inbox)
    return 'manual' if Current.user.present?

    'system'
  end

  def actor
    Current.user || Current.executed_by
  end

  def actor_id
    actor.respond_to?(:id) ? actor.id : nil
  end
end
