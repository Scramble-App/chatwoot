import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import isToday from 'date-fns/isToday';
import isYesterday from 'date-fns/isYesterday';
import { endOfDay, getUnixTime, startOfDay } from 'date-fns';
import { utcToZonedTime, zonedTimeToUtc } from 'date-fns-tz';

export const formatUnixDate = (date, dateFormat = 'MMM dd, yyyy') => {
  const unixDate = fromUnixTime(date);
  return format(unixDate, dateFormat);
};

export const formatDate = ({ date, todayText, yesterdayText }) => {
  const dateValue = new Date(date);
  if (isToday(dateValue)) return todayText;
  if (isYesterday(dateValue)) return yesterdayText;
  return date;
};

export const isTimeAfter = (h1, m1, h2, m2) => {
  if (h1 < h2) {
    return false;
  }

  if (h1 === h2) {
    return m1 >= m2;
  }

  return true;
};

/** Get start of day as a UNIX timestamp, for the calendar day of the date in the given timezone (browser timezone by default) */
export const getUnixStartOfDay = (date, timeZone) =>
  getUnixTime(
    timeZone ? zonedTimeToUtc(startOfDay(date), timeZone) : startOfDay(date)
  );

/** Get end of day as a UNIX timestamp, for the calendar day of the date in the given timezone (browser timezone by default) */
export const getUnixEndOfDay = (date, timeZone) =>
  getUnixTime(
    timeZone ? zonedTimeToUtc(endOfDay(date), timeZone) : endOfDay(date)
  );

/** Wall-clock time of a UNIX timestamp in the given timezone (browser timezone by default), to format or group by day and hour */
export const fromUnixTimeInZone = (timestamp, timeZone) =>
  timeZone
    ? utcToZonedTime(fromUnixTime(timestamp), timeZone)
    : fromUnixTime(timestamp);

export const generateRelativeTime = (value, unit, languageCode) => {
  const code = languageCode?.replace(/_/g, '-'); // Hacky fix we need to handle it from source
  const rtf = new Intl.RelativeTimeFormat(code, {
    numeric: 'auto',
  });
  return rtf.format(value, unit);
};
