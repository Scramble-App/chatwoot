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

    context 'with a special day' do
      # Monday, 1 June 2026, with weekly hours from 14:00 to 22:00
      let(:monday) { Date.new(2026, 6, 1) }

      before { create(:account_user_working_hour, account_user: account_user, day_of_week: 1, open_hour: 14, close_hour: 22) }

      def available_at?(time)
        account_user.reload.schedule_available_at?(Time.zone.parse("#{time} UTC"))
      end

      it 'takes the day off instead of the weekly hours' do
        create(:account_user_special_day, account_user: account_user, date: monday, day_off: true, open_hour: nil, close_hour: nil)

        expect(available_at?('2026-06-01 15:00')).to be(false)
      end

      it 'works only the special hours on that date' do
        create(:account_user_special_day, account_user: account_user, date: monday, open_hour: 10, close_hour: 18)

        expect([available_at?('2026-06-01 11:00'), available_at?('2026-06-01 20:00')]).to eq([true, false])
      end

      it 'goes back to the weekly hours on other dates' do
        create(:account_user_special_day, account_user: account_user, date: monday, day_off: true, open_hour: nil, close_hour: nil)

        expect(available_at?('2026-06-08 15:00')).to be(true)
      end

      it 'runs special hours that close before they open into the next morning' do
        create(:account_user_special_day, account_user: account_user, date: monday, open_hour: 20, close_hour: 2)

        expect(available_at?('2026-06-02 01:00')).to be(true)
      end
    end
  end

  describe '#upcoming_special_days' do
    it 'leaves out dates that have passed in the schedule timezone' do
      account_user.update!(schedule_timezone: 'Europe/Tallinn')
      today = create(:account_user_special_day, account_user: account_user, date: Date.new(2026, 6, 2))
      create(:account_user_special_day, account_user: account_user, date: Date.new(2026, 6, 1))

      # 23:30 UTC on 1 June is already 2 June in Tallinn
      travel_to Time.zone.parse('2026-06-01 23:30:00 UTC') do
        expect(account_user.reload.upcoming_special_days).to eq([today])
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
