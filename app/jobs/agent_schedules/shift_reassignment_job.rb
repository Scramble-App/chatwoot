class AgentSchedules::ShiftReassignmentJob < ApplicationJob
  queue_as :scheduled_jobs

  REASSIGNABLE_STATUSES = %w[open pending snoozed].freeze
  LOCK_TIMEOUT = 10.minutes

  def perform
    lock_manager = Redis::LockManager.new
    return unless lock_manager.lock(Redis::Alfred::AGENT_SHIFT_REASSIGNMENT_MUTEX, LOCK_TIMEOUT)

    begin
      reassign_off_shift_conversations
      assign_unassigned_conversations
    ensure
      lock_manager.unlock(Redis::Alfred::AGENT_SHIFT_REASSIGNMENT_MUTEX)
    end
  end

  private

  # Conversations of an agent whose shift ended move straight to an available agent.
  # When nobody is available they stay with the current agent and are retried on the next run.
  # The join skips account_users of deleted users, which User removes asynchronously.
  def reassign_off_shift_conversations
    AccountUser.where(schedule_enabled: true).joins(:user).includes(:account, :user, :working_hours, :schedule_exceptions)
               .find_each do |account_user|
      next if account_user.schedule_available_at?

      eligible_conversations(account_user).find_each do |conversation|
        reassign_conversation(conversation, account_user.user_id)
      end
    end
  end

  # Unassigned conversations (e.g. created overnight) get an assignee as soon as an agent is available.
  def assign_unassigned_conversations
    Inbox.where(enable_auto_assignment: true).includes(:account).find_each do |inbox|
      next unless inbox.auto_assignment_v2_enabled?

      statuses = assignable_statuses(inbox)
      next unless inbox.conversations.unassigned.exists?(status: statuses)
      next unless agent_capacity?(inbox)

      AutoAssignment::AssignmentJob.perform_now(inbox_id: inbox.id, statuses: statuses)
    end
  end

  def eligible_conversations(account_user)
    account_user.user.assigned_conversations
                .where(account_id: account_user.account_id, status: REASSIGNABLE_STATUSES)
                .joins(:team, :inbox)
                .where(teams: { allow_auto_assign: true, reassign_on_shift_end: true })
                .where(inboxes: { enable_auto_assignment: true })
  end

  def reassign_conversation(conversation, off_shift_user_id)
    inbox = conversation.inbox
    return unless inbox.auto_assignment_v2_enabled? && agent_capacity?(inbox)

    with_shift_end_assignment_source do
      AutoAssignment::AssignmentService.new(inbox: inbox).reassign(conversation) do |current|
        current.assignee_id == off_shift_user_id && REASSIGNABLE_STATUSES.include?(current.status)
      end
    end
  end

  # Pending conversations of an inbox with an active bot are still handled by the bot
  def assignable_statuses(inbox)
    inbox.active_bot? ? REASSIGNABLE_STATUSES - ['pending'] : REASSIGNABLE_STATUSES
  end

  # Checked once per inbox and run, so nights and rate-limited backlogs don't repeat the agent lookup per conversation
  def agent_capacity?(inbox)
    @agent_capacity ||= {}
    return @agent_capacity[inbox.id] if @agent_capacity.key?(inbox.id)

    @agent_capacity[inbox.id] = inbox.available_agents.any? do |inbox_member|
      AutoAssignment::RateLimiter.new(inbox: inbox, agent: inbox_member.user).within_limit?
    end
  end

  def with_shift_end_assignment_source
    previous_assignment_event_source = Current.assignment_event_source
    Current.assignment_event_source = 'shift_end'

    yield
  ensure
    Current.assignment_event_source = previous_assignment_event_source
  end
end
