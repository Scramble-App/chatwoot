# A conversation that leaves an agent while the customer is waiting for their reply counts as a conversation with no
# reply in agent reports. Only waiting in the agent's own shift counts, so moving a conversation on at the start of a
# shift after the customer wrote at night is not held against the agent who was off.
class ReportingEvents::HandoffWithoutReplyJob < ApplicationJob
  include ReportingEventHelper

  queue_as :low

  def perform(assignment_event, waiting_since)
    agent = assignment_event.from_assignee
    return if agent.blank?

    conversation = assignment_event.conversation
    handed_off_at = assignment_event.occurred_at
    start_time = [waiting_since, last_assigned_at(conversation, agent, handed_off_at)].compact.max
    business_seconds = business_hours(conversation.inbox, start_time, handed_off_at, user: agent)
    return unless business_seconds.positive?

    ReportingEvent.create!(
      name: 'agent_handoff_without_reply',
      value: handed_off_at.to_i - start_time.to_i,
      value_in_business_hours: business_seconds,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: agent.id,
      conversation_id: conversation.id,
      event_start_time: start_time,
      event_end_time: handed_off_at
    )
  end
end
