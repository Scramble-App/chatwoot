# == Schema Information
#
# Table name: account_user_working_hours
#
#  id              :bigint           not null, primary key
#  close_hour      :integer          not null
#  close_minutes   :integer          default(0), not null
#  day_of_week     :integer          not null
#  open_hour       :integer          not null
#  open_minutes    :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  account_user_id :bigint           not null
#
# Indexes
#
#  idx_account_user_working_hours_on_user_and_day       (account_user_id,day_of_week)
#  index_account_user_working_hours_on_account_id       (account_id)
#  index_account_user_working_hours_on_account_user_id  (account_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (account_user_id => account_users.id)
#
class AccountUserWorkingHour < ApplicationRecord
  belongs_to :account
  belongs_to :account_user

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :open_hour, :close_hour, inclusion: { in: 0..23 }
  validates :open_minutes, :close_minutes, inclusion: { in: 0..59 }

  before_validation :assign_account

  def open_at?(time)
    local_time = time.in_time_zone(account_user.schedule_time_zone)
    local_day = local_time.to_date.wday

    return within_minutes?(minutes_since_midnight(local_time)) if day_of_week == local_day
    return false unless overnight?

    previous_day = (local_day - 1) % 7
    day_of_week == previous_day && minutes_since_midnight(local_time) < close_minutes_since_midnight
  end

  private

  def assign_account
    self.account_id ||= account_user&.account_id
  end

  def within_minutes?(minutes)
    if overnight?
      minutes >= open_minutes_since_midnight
    else
      minutes >= open_minutes_since_midnight && minutes < close_minutes_since_midnight
    end
  end

  def overnight?
    close_minutes_since_midnight <= open_minutes_since_midnight
  end

  def open_minutes_since_midnight
    (open_hour * 60) + open_minutes
  end

  def close_minutes_since_midnight
    (close_hour * 60) + close_minutes
  end

  def minutes_since_midnight(time)
    (time.hour * 60) + time.min
  end
end
