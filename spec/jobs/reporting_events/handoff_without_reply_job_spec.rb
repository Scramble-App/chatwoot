require 'rails_helper'

RSpec.describe ReportingEvents::HandoffWithoutReplyJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:next_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:tallinn) { ActiveSupport::TimeZone['Europe/Tallinn'] }
  let(:schedule) { account.account_users.find_by(user: agent) }

  # The agent works from 07:00 to 14:00 on Monday, 28 September 2026
  before do
    schedule.update!(schedule_enabled: true, schedule_timezone: 'Europe/Tallinn')
    schedule.working_hours.create!(day_of_week: 1, open_hour: 7, close_hour: 14)
  end

  def at(day, hour, minute = 0)
    tallinn.local(2026, 9, day, hour, minute)
  end

  def customer_writes(at)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: at)
  end

  def hand_off(at:, assigned_at: at(28, 7), to: next_agent)
    create(:conversation_assignment_event, conversation: conversation, to_assignee: agent, occurred_at: assigned_at)
    create(:conversation_assignment_event, conversation: conversation, from_assignee: agent, to_assignee: to,
                                           event_type: to ? 'reassigned' : 'unassigned', source: 'shift_end', occurred_at: at)
  end

  def no_reply_events
    account.reporting_events.where(name: 'agent_handoff_without_reply')
  end

  it 'counts a customer left waiting in the agent shift against the agent, on the day of the handoff' do
    customer_writes(at(28, 13, 30))

    described_class.perform_now(hand_off(at: at(28, 14, 5)), at(28, 13, 30))

    expect(no_reply_events.sole).to have_attributes(user_id: agent.id, conversation_id: conversation.id, value: 35.minutes,
                                                    value_in_business_hours: 30.minutes, created_at: at(28, 14, 5))
  end

  it 'times the wait from when the agent got the conversation' do
    customer_writes(at(28, 12))

    described_class.perform_now(hand_off(at: at(28, 14), assigned_at: at(28, 13, 50)), at(28, 12))

    expect(no_reply_events.sole.value).to eq 10.minutes
  end

  it 'counts a conversation left without an assignee' do
    customer_writes(at(28, 13))

    described_class.perform_now(hand_off(at: at(28, 13, 20), to: nil), at(28, 13))

    expect(no_reply_events.sole.value).to eq 20.minutes
  end

  it 'does not count a customer who wrote after the agent shift ended' do
    customer_writes(at(28, 20))

    described_class.perform_now(hand_off(at: at(29, 7)), at(28, 20))

    expect(no_reply_events).to be_empty
  end

  it 'does not count a conversation the customer has not written in yet' do
    described_class.perform_now(hand_off(at: at(28, 13)), at(28, 10))

    expect(no_reply_events).to be_empty
  end

  it 'measures an agent without a schedule like the inbox' do
    schedule.update!(schedule_enabled: false)
    customer_writes(at(28, 20))

    # The inbox has no scheduled agents and no business hours, so the whole wait counts
    described_class.perform_now(hand_off(at: at(29, 7)), at(28, 20))

    expect(no_reply_events.sole.value_in_business_hours).to eq 11.hours
  end

  it 'records a real handoff while the customer waits' do
    waiting_conversation = travel_to(at(28, 13)) do
      create(:conversation, account: account, inbox: inbox, assignee: agent).tap do |created|
        create(:message, account: account, inbox: inbox, conversation: created, message_type: :incoming)
      end
    end

    # The class is looked up when the job is enqueued: the full suite can reload job classes, and described_class keeps the old one
    handoff_job = ->(job) { job.is_a?(ReportingEvents::HandoffWithoutReplyJob) } # rubocop:disable RSpec/DescribedClass
    travel_to(at(28, 13, 30)) do
      perform_enqueued_jobs(only: handoff_job) { waiting_conversation.update!(assignee: next_agent) }
    end

    expect(no_reply_events.sole).to have_attributes(user_id: agent.id, value: 30.minutes)
  end
end
