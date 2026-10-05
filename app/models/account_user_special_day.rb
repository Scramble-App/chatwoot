# == Schema Information
#
# Table name: account_user_special_days
#
#  id              :bigint           not null, primary key
#  close_hour      :integer
#  close_minutes   :integer          default(0), not null
#  date            :date             not null
#  day_off         :boolean          default(FALSE), not null
#  open_hour       :integer
#  open_minutes    :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  account_user_id :bigint           not null
#
# Indexes
#
#  idx_account_user_special_days_on_user_and_date      (account_user_id,date)
#  index_account_user_special_days_on_account_id       (account_id)
#  index_account_user_special_days_on_account_user_id  (account_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (account_user_id => account_users.id)
#
# A date on which an agent works other hours than their weekly ones, or not at all, e.g. to cover for a colleague's
# day off. It replaces the weekly hours of that date in the agent's schedule timezone, and has no effect on other dates.
class AccountUserSpecialDay < ApplicationRecord
  include ShiftHours

  belongs_to :account
  belongs_to :account_user

  before_validation :assign_account

  validates :date, presence: true
  validates :open_hour, :close_hour, inclusion: { in: 0..23 }, unless: :day_off?
  validates :open_minutes, :close_minutes, inclusion: { in: 0..59 }

  private

  def assign_account
    self.account_id ||= account_user&.account_id
  end
end
