import timeZoneData from '../../inbox/helpers/timezones.json';

export const DEFAULT_AGENT_SCHEDULE_TIMEZONE = 'Europe/Tallinn';
const ADDITIONAL_TIMEZONE_IDS = ['UTC'];

const fallbackTimezoneIds = () => Object.values(timeZoneData);

const supportedTimezoneIds = () => {
  if (typeof Intl.supportedValuesOf !== 'function') {
    return fallbackTimezoneIds();
  }

  return Intl.supportedValuesOf('timeZone');
};

export const agentScheduleTimezoneOptions = () => {
  const timezoneIds = [
    ...new Set([...ADDITIONAL_TIMEZONE_IDS, ...supportedTimezoneIds()]),
  ];

  return timezoneIds.map(timezone => ({
    label: timezone,
    value: timezone,
  }));
};
