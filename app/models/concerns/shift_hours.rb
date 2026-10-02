# Opening and closing time of an agent's shift on a day. A shift that does not close after it opens runs overnight,
# so 22:00 to 06:00 ends the next morning and 18:00 to 00:00 ends at midnight.
module ShiftHours
  extend ActiveSupport::Concern

  # [start, finish) of the shift on the date, in the zone
  def shift_on(date, zone)
    close_date = overnight? ? date + 1.day : date
    [zone.local(date.year, date.month, date.day, open_hour, open_minutes),
     zone.local(close_date.year, close_date.month, close_date.day, close_hour, close_minutes)]
  end

  private

  def overnight?
    (close_hour * 60) + close_minutes <= (open_hour * 60) + open_minutes
  end
end
