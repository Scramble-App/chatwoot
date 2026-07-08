# frozen_string_literal: true

FactoryBot.define do
  factory :account_user_schedule_exception do
    account_user
    account { account_user.account }
    starts_at { 1.hour.from_now }
    ends_at { 2.hours.from_now }
    available { false }
  end
end
