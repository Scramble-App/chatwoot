require 'rails_helper'

RSpec.describe ReportingEvents::BusinessTimeRecalculationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:tallinn) { ActiveSupport::TimeZone['Europe/Tallinn'] }
  # A customer waited from Monday 13:00 to Tuesday 08:00; the agent's shift is 07:00 to 14:00 on weekdays
  let!(:reply_event) do
    create(:reporting_event, account: account, inbox: inbox, name: 'reply_time', value: 19.hours, value_in_business_hours: 0,
                             event_start_time: tallinn.local(2026, 9, 28, 13), event_end_time: tallinn.local(2026, 9, 29, 8),
                             created_at: tallinn.local(2026, 9, 29, 8))
  end

  before do
    user = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: user)
    account_user = account.account_users.find_by(user: user)
    account_user.update!(schedule_enabled: true, schedule_timezone: 'Europe/Tallinn')
    (1..5).each { |day| account_user.working_hours.create!(day_of_week: day, open_hour: 7, close_hour: 14) }
  end

  it 'recalculates the business time of past events from the shifts' do
    service = described_class.new(account: account).perform

    expect(reply_event.reload.value_in_business_hours).to eq 2.hours
    expect(service.changed_count).to eq 1
  end

  it 'keeps the first opening of a conversation at 0' do
    opening = create(:reporting_event, account: account, inbox: inbox, name: 'conversation_opened', value: 0, value_in_business_hours: 0)

    described_class.new(account: account).perform

    expect(opening.reload.value_in_business_hours).to eq 0
  end

  it 'only counts the changes in a dry run' do
    service = described_class.new(account: account, dry_run: true).perform

    expect(service.changed_count).to eq 1
    expect(reply_event.reload.value_in_business_hours).to eq 0
  end

  it 'leaves events before the given start alone' do
    described_class.new(account: account, since: tallinn.local(2026, 9, 30)).perform

    expect(reply_event.reload.value_in_business_hours).to eq 0
  end

  it 'skips events of a deleted inbox' do
    reply_event.update!(inbox_id: inbox.id + 1000)

    expect(described_class.new(account: account).perform.changed_count).to eq 0
  end

  it 'rebuilds the rollups of the changed days when the account collects them' do
    account.update!(reporting_timezone: 'Europe/Tallinn')
    allow(ReportingEvents::BackfillService).to receive(:backfill_date)

    described_class.new(account: account).perform

    expect(ReportingEvents::BackfillService).to have_received(:backfill_date).with(account, Date.new(2026, 9, 29)).once
  end

  it 'does not touch rollups in a dry run' do
    account.update!(reporting_timezone: 'Europe/Tallinn')
    allow(ReportingEvents::BackfillService).to receive(:backfill_date)

    described_class.new(account: account, dry_run: true).perform

    expect(ReportingEvents::BackfillService).not_to have_received(:backfill_date)
  end
end
