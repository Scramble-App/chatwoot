import { ref } from 'vue';
import { useReportTimezone } from '../useReportTimezone';
import { useAccount } from 'dashboard/composables/useAccount';

vi.mock('dashboard/composables/useAccount');

const reportTimezoneFor = settings => {
  useAccount.mockReturnValue({ currentAccount: ref({ id: 1, settings }) });
  return useReportTimezone().value;
};

describe('useReportTimezone', () => {
  it('returns the account reports timezone', () => {
    expect(reportTimezoneFor({ reporting_timezone: 'Europe/Tallinn' })).toBe(
      'Europe/Tallinn'
    );
  });

  it('follows the browser timezone when none is set', () => {
    expect(reportTimezoneFor({})).toBeNull();
  });

  it('follows the browser timezone for a name the browser does not know', () => {
    expect(reportTimezoneFor({ reporting_timezone: 'Tallinn' })).toBeNull();
  });
});
