# == Schema Information
#
# Table name: account_user_schedule_exceptions
#
#  id              :bigint           not null, primary key
#  available       :boolean          default(FALSE), not null
#  ends_at         :datetime         not null
#  name            :string
#  starts_at       :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  account_user_id :bigint           not null
#
# Indexes
#
#  idx_account_user_schedule_exceptions_on_range              (account_user_id,starts_at,ends_at)
#  index_account_user_schedule_exceptions_on_account_id       (account_id)
#  index_account_user_schedule_exceptions_on_account_user_id  (account_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (account_user_id => account_users.id)
#
class AccountUserScheduleException < ApplicationRecord
  belongs_to :account
  belongs_to :account_user

  before_validation :assign_account

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts

  scope :active_at, ->(time) { where('starts_at <= ? AND ends_at > ?', time, time) }

  private

  def assign_account
    self.account_id ||= account_user&.account_id
  end

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, 'must be after starts_at')
  end
end
