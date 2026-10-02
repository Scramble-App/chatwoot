# frozen_string_literal: true

FactoryBot.define do
  factory :account_user_special_day do
    account_user
    account { account_user.account }
    date { Date.current }
    day_off { false }
    open_hour { 10 }
    open_minutes { 0 }
    close_hour { 18 }
    close_minutes { 0 }
  end
end
