# frozen_string_literal: true

FactoryBot.define do
  factory :account_user_working_hour do
    account_user
    account { account_user.account }
    day_of_week { 1 }
    open_hour { 9 }
    open_minutes { 0 }
    close_hour { 18 }
    close_minutes { 0 }
  end
end
