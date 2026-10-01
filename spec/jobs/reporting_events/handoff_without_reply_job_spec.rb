require 'rails_helper'

RSpec.describe ReportingEvents::HandoffWithoutReplyJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:next_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:tallinn) { ActiveSupport::TimeZone['Europe/Tallinn'] }

  # The agent works from 07:00 to 14:00 on Monday, 28 September 2026
  before do
    account_user = account.account_users.find_by(user: agent)
    account_user.update!(schedule_enabled: true, schedule_timezone: 'Europe/Tallinn')
    account_user.working_hours.create!(day_of_week: 1, open_hour: 7, close_hour: 14)
  end

  def at(day, hour, minute = 0)
    tallinn.local(2026, 9, day, hour, minute)
  end

  def hand_off(at:, assigned_at: at(28, 7))
    create(:conversation_assignment_event, conversation: conversation, to_assignee: agent, occurred_at: assigned_at)
    create(:conversation_assignment_event, conversation: conversation, from_assignee: agent, to_assignee: next_agent,
                                           event_type: 'reassigned', source: 'shift_end', occurred_at: at)
  end

  def no_reply_events
    account.reporting_events.where(name: 'agent_handoff_without_reply')
  end

  it 'counts a customer left waiting in the agent shift against the agent' do
    described_class.perform_now(hand_off(at: at(28, 14, 5)), at(28, 13, 30))

    expect(no_reply_events.sole).to have_attributes(user_id: agent.id, conversation_id: conversation.id,
                                                    value: 35.minutes, value_in_business_hours: 30.minutes)
  end

  it 'times the wait from when the agent got the conversation' do
    described_class.perform_now(hand_off(at: at(28, 14), assigned_at: at(28, 13, 50)), at(28, 12))

    expect(no_reply_events.sole.value).to eq 10.minutes
  end

  it 'does not count a customer who wrote after the agent shift ended' do
    described_class.perform_now(hand_off(at: at(29, 7)), at(28, 20))

    expect(no_reply_events).to be_empty
  end
end
