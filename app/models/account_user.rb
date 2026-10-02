# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  role                     :integer          default("agent")
#  schedule_enabled         :boolean          default(FALSE), not null
#  schedule_timezone        :string
#  translation_locale       :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  DEFAULT_SCHEDULE_TIMEZONE = 'Europe/Tallinn'.freeze

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  # Deleted inline: destroy_async would delete them after the account user, and their foreign keys block that.
  # delete_all rather than destroy because they have no destroy callbacks.
  has_many :working_hours, class_name: 'AccountUserWorkingHour', dependent: :delete_all
  has_many :special_days, class_name: 'AccountUserSpecialDay', dependent: :delete_all

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account
  accepts_nested_attributes_for :working_hours, allow_destroy: true

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?

  validates :user_id, uniqueness: { scope: :account_id }
  validates :translation_locale, length: { maximum: 20 }, allow_blank: true
  validates :schedule_timezone, inclusion: { in: TZInfo::Timezone.all_identifiers }, allow_blank: true

  def schedule_time_zone
    schedule_timezone.presence || account.reporting_timezone.presence || DEFAULT_SCHEDULE_TIMEZONE
  end

  def availability_source
    schedule_enabled? ? 'schedule' : 'manual'
  end

  def scheduled_availability_at(time = Time.current)
    schedule_available_at?(time) ? 'online' : 'offline'
  end

  def schedule_available_at?(time = Time.current)
    local_date = time.in_time_zone(schedule_time_zone).to_date
    # A shift of the day before can still run overnight
    [local_date - 1.day, local_date].any? do |date|
      schedule_shifts_on(date).any? { |start, finish| start <= time && time < finish }
    end
  end

  # [start, finish) of the shifts of a date in the schedule timezone: its special schedule if it has one, otherwise its
  # weekly hours
  def schedule_shifts_on(date)
    special = special_days.select { |special_day| special_day.date == date }
    hours = special.any? ? special.reject(&:day_off?) : working_hours.select { |working_hour| working_hour.day_of_week == date.wday }
    zone = ActiveSupport::TimeZone[schedule_time_zone]
    hours.map { |hour| hour.shift_on(date, zone) }
  end

  # Special days from today on in the schedule timezone, since past ones no longer apply
  def upcoming_special_days
    today = Time.current.in_time_zone(schedule_time_zone).to_date
    special_days.select { |special_day| special_day.date >= today }.sort_by { |special_day| [special_day.date, special_day.open_hour.to_i] }
  end

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account, user)
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      availability_status: availability_status,
      availability_source: availability_source,
      schedule_enabled: schedule_enabled?,
      role: role,
      user_id: user_id
    }
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
