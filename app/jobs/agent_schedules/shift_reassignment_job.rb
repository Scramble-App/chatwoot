class AgentSchedules::ShiftReassignmentJob < ApplicationJob
  queue_as :scheduled_jobs

  REASSIGNABLE_STATUSES = %w[open pending snoozed].freeze

  def perform
    AccountUser.where(schedule_enabled: true).includes(:account, :user, :working_hours, :schedule_exceptions).find_each do |account_user|
      next if account_user.schedule_available_at?

      reassign_off_shift_conversations(account_user)
    end
  end

  private

  def reassign_off_shift_conversations(account_user)
    inbox_ids = []

    eligible_conversations(account_user).find_each do |conversation|
      next unless unassign_conversation(conversation)

      inbox_ids << conversation.inbox_id
    end

    inbox_ids.uniq.each do |inbox_id|
      AutoAssignment::AssignmentJob.perform_later(inbox_id: inbox_id, statuses: REASSIGNABLE_STATUSES)
    end
  end

  def eligible_conversations(account_user)
    account_user.user.assigned_conversations
                .where(account_id: account_user.account_id, status: REASSIGNABLE_STATUSES)
                .joins(:team, :inbox)
                .where(teams: { allow_auto_assign: true, reassign_on_shift_end: true })
                .where(inboxes: { enable_auto_assignment: true })
  end

  def unassign_conversation(conversation)
    with_shift_end_assignment_source do
      conversation.with_lock do
        if eligible_for_unassignment?(conversation)
          conversation.update!(assignee: nil)
          true
        else
          false
        end
      end
    end
  end

  def eligible_for_unassignment?(conversation)
    assigned_reassignable_conversation?(conversation) &&
      shift_reassignment_enabled?(conversation.team) &&
      conversation.inbox&.enable_auto_assignment?
  end

  def assigned_reassignable_conversation?(conversation)
    conversation.assignee_id.present? && REASSIGNABLE_STATUSES.include?(conversation.status)
  end

  def shift_reassignment_enabled?(team)
    team&.allow_auto_assign? && team&.reassign_on_shift_end?
  end

  def with_shift_end_assignment_source
    previous_assignment_event_source = Current.assignment_event_source
    Current.assignment_event_source = 'shift_end'

    yield
  ensure
    Current.assignment_event_source = previous_assignment_event_source
  end
end
