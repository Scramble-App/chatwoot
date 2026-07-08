# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      expect(account_user.user.notification_settings).not_to be_nil

      expect(account_user.user.notification_settings.first.email_conversation_creation?).to be(false)
      expect(account_user.user.notification_settings.first.email_conversation_assignment?).to be(true)
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  describe 'schedule availability' do
    before do
      account_user.update!(schedule_enabled: true, schedule_timezone: 'UTC')
    end

    it 'returns online during a matching weekly interval' do
      create(:account_user_working_hour, account_user: account_user, day_of_week: 1, open_hour: 9, close_hour: 18)

      travel_to Time.zone.parse('2026-06-01 10:00:00 UTC') do
        expect(account_user.availability_status).to eq('online')
      end
    end

    it 'returns offline outside weekly intervals' do
      create(:account_user_working_hour, account_user: account_user, day_of_week: 1, open_hour: 9, close_hour: 18)

      travel_to Time.zone.parse('2026-06-01 20:00:00 UTC') do
        expect(account_user.availability_status).to eq('offline')
      end
    end

    it 'supports overnight intervals' do
      create(:account_user_working_hour, account_user: account_user, day_of_week: 0, open_hour: 22, close_hour: 2)

      travel_to Time.zone.parse('2026-06-01 01:00:00 UTC') do
        expect(account_user.availability_status).to eq('online')
      end
    end

    it 'lets exceptions override weekly intervals' do
      create(:account_user_working_hour, account_user: account_user, day_of_week: 1, open_hour: 9, close_hour: 18)
      create(
        :account_user_schedule_exception,
        account_user: account_user,
        starts_at: Time.zone.parse('2026-06-01 09:00:00 UTC'),
        ends_at: Time.zone.parse('2026-06-01 12:00:00 UTC'),
        available: false
      )

      travel_to Time.zone.parse('2026-06-01 10:00:00 UTC') do
        expect(account_user.availability_status).to eq('offline')
      end
    end
  end

  describe '#schedule_time_zone' do
    it 'falls back to Tallinn when no account or agent timezone is set' do
      account_user.account.update!(settings: {})
      account_user.update!(schedule_timezone: nil)

      expect(account_user.schedule_time_zone).to eq('Europe/Tallinn')
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end
end
