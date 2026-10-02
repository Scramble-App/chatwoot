require 'rails_helper'

RSpec.describe ReportingEvents::BusinessTime do
  subject(:business_time) { described_class.new(inbox) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tallinn) { ActiveSupport::TimeZone['Europe/Tallinn'] }
  # Monday, 28 September 2026
  let(:monday) { Date.new(2026, 9, 28) }

  def at(day, hour, minute = 0)
    tallinn.local(day.year, day.month, day.day, hour, minute)
  end

  def scheduled_agent(shifts, member: true, enabled: true)
    user = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: user) if member
    account_user = account.account_users.find_by(user: user)
    account_user.update!(schedule_enabled: enabled, schedule_timezone: 'Europe/Tallinn')
    shifts.each do |day_of_week, (open_hour, close_hour)|
      account_user.working_hours.create!(day_of_week: day_of_week, open_hour: open_hour, close_hour: close_hour)
    end
    account_user
  end

  def weekdays(open_hour, close_hour)
    (1..5).index_with { [open_hour, close_hour] }
  end

  context 'with agents on shift' do
    let!(:morning_agent) { scheduled_agent(weekdays(7, 14)) }

    before { scheduled_agent(weekdays(14, 22)) }

    it 'counts time inside a shift' do
      expect(business_time.seconds_between(at(monday, 10), at(monday, 11))).to eq 1.hour
    end

    it 'leaves out the night between shifts' do
      expect(business_time.seconds_between(at(monday, 21), at(monday + 1, 8))).to eq 2.hours
    end

    it 'leaves out the weekend' do
      expect(business_time.seconds_between(at(monday + 4, 21, 30), at(monday + 7, 7, 30))).to eq 1.hour
    end

    it 'leaves out time off of the only agent on shift' do
      morning_agent.schedule_exceptions.create!(starts_at: at(monday, 0), ends_at: at(monday + 1, 0), available: false)

      expect(business_time.seconds_between(at(monday, 7), at(monday, 15))).to eq 1.hour
    end

    it 'leaves out a special day off of the only agent on shift' do
      morning_agent.special_days.create!(date: monday, day_off: true)

      expect(business_time.seconds_between(at(monday, 7), at(monday, 15))).to eq 1.hour
    end

    it 'counts the special hours of a date instead of the weekly ones' do
      morning_agent.special_days.create!(date: monday, open_hour: 9, close_hour: 11)

      # 09:00 to 11:00 of the morning agent, and 14:00 to 15:00 of the evening agent
      expect(business_time.seconds_between(at(monday, 7), at(monday, 15))).to eq 3.hours
    end

    it 'counts an extra shift outside the weekly hours' do
      morning_agent.schedule_exceptions.create!(starts_at: at(monday + 5, 10), ends_at: at(monday + 5, 12), available: true)

      expect(business_time.seconds_between(at(monday + 5, 9), at(monday + 5, 13))).to eq 2.hours
    end

    it 'ignores scheduled agents of other inboxes' do
      scheduled_agent({ 6 => [0, 23] }, member: false)

      expect(business_time.seconds_between(at(monday + 5, 9), at(monday + 5, 13))).to eq 0
    end

    it 'returns 0 for an empty or reversed span' do
      expect(business_time.seconds_between(at(monday, 11), at(monday, 10))).to eq 0
    end
  end

  it 'counts overlapping shifts once' do
    scheduled_agent(weekdays(7, 14))
    scheduled_agent(weekdays(12, 18))

    expect(business_time.seconds_between(at(monday, 6), at(monday, 19))).to eq 11.hours
  end

  it 'runs a shift that closes before it opens overnight' do
    scheduled_agent({ 1 => [22, 6] })

    expect(business_time.seconds_between(at(monday, 23), at(monday + 1, 7))).to eq 7.hours
  end

  it 'runs a shift that closes at midnight until the end of the day' do
    scheduled_agent({ 1 => [18, 0] })

    expect(business_time.seconds_between(at(monday, 17), at(monday + 1, 1))).to eq 6.hours
  end

  it 'counts a shift on the day the clocks go back by its real length' do
    # Tallinn leaves summer time on Sunday 25 October 2026 at 04:00, so 00:00 to 06:00 lasts 7 hours
    scheduled_agent({ 0 => [0, 6] })

    expect(business_time.seconds_between(at(monday + 26, 23), at(monday + 27, 7))).to eq 7.hours
  end

  it 'follows the exception that started last when exceptions overlap' do
    agent = scheduled_agent(weekdays(7, 14))
    agent.schedule_exceptions.create!(starts_at: at(monday, 0), ends_at: at(monday + 1, 0), available: false)
    agent.schedule_exceptions.create!(starts_at: at(monday, 10), ends_at: at(monday, 12), available: true)

    expect(business_time.seconds_between(at(monday, 7), at(monday, 14))).to eq 2.hours
  end

  it "measures an agent's own reply in their own shifts" do
    scheduled_agent(weekdays(7, 14))
    evening_agent = scheduled_agent(weekdays(14, 22))

    expect(described_class.new(inbox, user: evening_agent.user).seconds_between(at(monday, 13), at(monday, 15))).to eq 1.hour
  end

  it 'measures an agent without a schedule like the inbox' do
    scheduled_agent(weekdays(7, 14))
    agent = create(:user, account: account, role: :agent)

    expect(described_class.new(inbox, user: agent).seconds_between(at(monday, 13), at(monday, 15))).to eq 1.hour
  end

  it 'ignores agents whose schedule is off' do
    scheduled_agent(weekdays(7, 14), enabled: false)

    expect(business_time.seconds_between(at(monday, 6), at(monday, 8))).to eq 2.hours
  end

  context 'without scheduled agents' do
    it 'uses the inbox business hours when they are on' do
      inbox.update!(working_hours_enabled: true, timezone: 'Europe/Tallinn')

      # Default inbox hours are 09:00 to 17:00 on weekdays
      expect(business_time.seconds_between(at(monday, 8), at(monday, 10))).to eq 1.hour
    end

    it 'counts the whole span when the inbox business hours are off' do
      expect(business_time.seconds_between(at(monday + 5, 9), at(monday + 6, 9))).to eq 1.day
    end
  end
end
