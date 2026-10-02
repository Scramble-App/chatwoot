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
  include ShiftHours

  belongs_to :account
  belongs_to :account_user

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :open_hour, :close_hour, inclusion: { in: 0..23 }
  validates :open_minutes, :close_minutes, inclusion: { in: 0..59 }

  before_validation :assign_account

  private

  def assign_account
    self.account_id ||= account_user&.account_id
  end
end
