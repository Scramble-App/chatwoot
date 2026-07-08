namespace :conversation_assignment_events do
  desc 'Create initial assignment history snapshot for assigned non-resolved conversations'
  task snapshot: :environment do
    statuses = Conversation.statuses.slice('open', 'pending', 'snoozed').values

    Conversation.where(status: statuses).where.not(assignee_id: nil).find_each do |conversation|
      next if conversation.assignment_events.exists?(source: 'snapshot', event_type: 'snapshot')

      ConversationAssignmentEvents::Recorder.record!(
        conversation: conversation,
        from_assignee_id: nil,
        to_assignee_id: conversation.assignee_id,
        source: 'snapshot',
        occurred_at: Time.current,
        metadata: { assigned_at_exact: false }
      )
    end
  end
end
