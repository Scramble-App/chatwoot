require 'rails_helper'

RSpec.describe Conversations::ReopenSnoozedConversationsJob do
  let!(:snoozed_till_5_minutes_ago) { create(:conversation, status: :snoozed, snoozed_until: 5.minutes.ago) }
  let!(:snoozed_till_tomorrow) { create(:conversation, status: :snoozed, snoozed_until: 1.day.from_now) }
  let!(:snoozed_indefinitely) { create(:conversation, status: :snoozed) }

  it 'enqueues the job' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  context 'when called' do
    it 'reopens snoozed conversations whose snooze until has passed' do
      described_class.perform_now

      expect(snoozed_till_5_minutes_ago.reload.status).to eq 'open'
      expect(snoozed_till_tomorrow.reload.status).to eq 'snoozed'
      expect(snoozed_indefinitely.reload.status).to eq 'snoozed'
    end

    it 'marks the reopened conversation as waiting for an agent reply' do
      snoozed_till_5_minutes_ago.update!(waiting_since: nil, last_activity_at: 2.days.ago)

      freeze_time do
        described_class.perform_now

        expect(snoozed_till_5_minutes_ago.reload.waiting_since).to eq Time.current
        expect(snoozed_till_5_minutes_ago.last_activity_at).to eq Time.current
      end
    end

    it 'keeps the time a customer has already been waiting since' do
      snoozed_till_5_minutes_ago.update!(waiting_since: 1.day.ago.beginning_of_minute)

      described_class.perform_now

      expect(snoozed_till_5_minutes_ago.reload.waiting_since).to eq 1.day.ago.beginning_of_minute
    end
  end

  # The agent snoozed after replying "we will get back to you", so auto-resolve must not close the reminder right away
  context 'with auto-resolve after 30 minutes' do
    let(:account) { snoozed_till_5_minutes_ago.account }

    before do
      snoozed_till_5_minutes_ago.update!(waiting_since: nil, last_activity_at: 2.days.ago)
    end

    it 'keeps the reopened conversation open until an agent replies when waiting conversations are skipped' do
      account.update!(auto_resolve_after: 30, auto_resolve_ignore_waiting: true)

      described_class.perform_now
      travel_to(1.hour.from_now) { Conversations::ResolutionJob.perform_now(account: account) }

      expect(snoozed_till_5_minutes_ago.reload.status).to eq 'open'
    end

    it 'does not resolve the reopened conversation right away when all conversations are resolved' do
      account.update!(auto_resolve_after: 30, auto_resolve_ignore_waiting: false)

      described_class.perform_now
      Conversations::ResolutionJob.perform_now(account: account)

      expect(snoozed_till_5_minutes_ago.reload.status).to eq 'open'
    end
  end
end
