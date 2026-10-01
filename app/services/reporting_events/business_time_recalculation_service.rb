# Recalculates the business time of an account's past reporting events with ReportingEvents::BusinessTime, so
# business hours reports also cover the time before agent shifts were counted. It uses the shifts as they are
# now, and rebuilds the daily rollups of the changed days when the account collects rollups.
class ReportingEvents::BusinessTimeRecalculationService
  EVENT_NAMES = %w[first_response reply_time conversation_resolved conversation_bot_resolved conversation_bot_handoff conversation_opened].freeze

  attr_reader :changed_count

  def initialize(account:, since: nil, dry_run: false)
    @account = account
    @since = since
    @dry_run = dry_run
    @changed_count = 0
    @changed_dates = Set.new
  end

  def perform
    events.find_each { |event| recalculate(event) }
    rebuild_rollups unless dry_run
    self
  end

  private

  attr_reader :account, :since, :dry_run

  def events
    scope = account.reporting_events.where(name: EVENT_NAMES).where.not(event_start_time: nil).where.not(event_end_time: nil)
    since ? scope.where(created_at: since..) : scope
  end

  def recalculate(event)
    value = business_seconds(event)
    return if value.nil? || value == event.value_in_business_hours

    @changed_count += 1
    @changed_dates << event.created_at
    # rubocop:disable Rails/SkipsModelValidations
    event.update_columns(value_in_business_hours: value) unless dry_run
    # rubocop:enable Rails/SkipsModelValidations
  end

  # An event without a duration, such as the first opening of a conversation, has no business time either
  def business_seconds(event)
    return 0 if event.value.to_f.zero?

    calculators[event.inbox_id]&.seconds_between(event.event_start_time, event.event_end_time)
  end

  # One calculator per inbox, so its agent schedules are loaded once; events of a deleted inbox are skipped
  def calculators
    @calculators ||= Hash.new do |calculators, inbox_id|
      inbox = account.inboxes.find_by(id: inbox_id)
      calculators[inbox_id] = inbox && ReportingEvents::BusinessTime.new(inbox)
    end
  end

  def rebuild_rollups
    zone = ActiveSupport::TimeZone[account.reporting_timezone.to_s]
    return if zone.blank?

    @changed_dates.map { |time| time.in_time_zone(zone).to_date }.uniq.each do |date|
      ReportingEvents::BackfillService.backfill_date(account, date)
    end
  end
end
