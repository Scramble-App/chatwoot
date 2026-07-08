import {
  DEFAULT_AGENT_SCHEDULE_TIMEZONE,
  agentScheduleTimezoneOptions,
} from '../timezone';

describe('#agentScheduleTimezoneOptions', () => {
  it('uses Europe/Tallinn as the default agent schedule timezone', () => {
    expect(DEFAULT_AGENT_SCHEDULE_TIMEZONE).toBe('Europe/Tallinn');
  });

  it('returns IANA timezone options', () => {
    const options = agentScheduleTimezoneOptions();

    expect(options).toContainEqual({
      label: 'UTC',
      value: 'UTC',
    });
    expect(options).toContainEqual({
      label: 'Europe/Tallinn',
      value: 'Europe/Tallinn',
    });
  });
});
