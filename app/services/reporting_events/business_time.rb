# Business time of a span for an inbox's reports: the part of it when at least one inbox agent was on shift,
# following each agent's weekly hours and special days the same way as AccountUser#schedule_available_at?.
# An inbox without scheduled agents falls back to its business hours, and to the whole span when those are off,
# so a business hours report never shows 0 for that inbox.
# With a user, e.g. for how fast an agent replied, the span is measured in that agent's own shifts when they have a
# schedule, and like the inbox's otherwise.
class ReportingEvents::BusinessTime
  WEEK_DAYS = %i[sun mon tue wed thu fri sat].freeze

  def initialize(inbox, user: nil)
    @inbox = inbox
    @user = user
  end

  def seconds_between(from, to)
    return 0 if from.blank? || to.blank? || to <= from
    return shift_seconds(from, to) if scheduled_agents.any?
    return inbox_hours_seconds(from, to) if inbox.working_hours_enabled?

    (to - from).round
  end

  private

  attr_reader :inbox, :user

  def scheduled_agents
    @scheduled_agents ||= own_schedule.presence || schedules.where(user_id: inbox.inbox_members.select(:user_id)).to_a
  end

  def own_schedule
    user ? schedules.where(user_id: user.id).to_a : []
  end

  def schedules
    inbox.account.account_users.joins(:user).where(schedule_enabled: true).includes(:account, :working_hours, :special_days)
  end

  # The span is cut at every shift edge, so each piece is either fully on shift or fully off
  def shift_seconds(from, to)
    shifts = scheduled_agents.flat_map { |agent| shifts_between(agent, from, to) }
    points = (shifts.flatten.select { |edge| edge > from && edge < to } + [from, to]).uniq.sort

    points.each_cons(2).sum { |start, finish| on_shift?(shifts, start) ? finish - start : 0 }.round
  end

  def on_shift?(shifts, time)
    shifts.any? { |start, finish| start <= time && time < finish }
  end

  # [start, finish) of every shift that touches the span; the day before the span can run overnight into it
  def shifts_between(agent, from, to)
    zone = ActiveSupport::TimeZone[agent.schedule_time_zone]
    days = (from.in_time_zone(zone).to_date - 1.day)..to.in_time_zone(zone).to_date

    days.flat_map { |day| agent.schedule_shifts_on(day) }
  end

  def inbox_hours_seconds(from, to)
    working_hours = inbox.working_hours.reject(&:closed_all_day?).to_h do |hour|
      [WEEK_DAYS[hour.day_of_week], { format_time(hour.open_hour, hour.open_minutes) => format_time(hour.close_hour, hour.close_minutes) }]
    end
    return 0 if working_hours.blank?

    WorkingHours::Config.with_config(working_hours: working_hours, time_zone: inbox.timezone) do
      from.in_time_zone(inbox.timezone).to_time.working_time_until(to.in_time_zone(inbox.timezone).to_time)
    end
  end

  def format_time(hour, minute)
    format('%<hour>02d:%<minute>02d', hour: hour, minute: minute)
  end
end
