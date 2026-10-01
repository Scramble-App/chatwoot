import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

// Like the backend, reports only use a timezone the browser knows, e.g. not a Rails name such as "Tallinn"
const isKnownTimezone = timeZone => {
  try {
    Intl.DateTimeFormat(undefined, { timeZone });
    return true;
  } catch {
    return false;
  }
};

/**
 * The account's reports timezone, or null when reports follow the browser timezone.
 * @returns {import('vue').ComputedRef<string|null>}
 */
export function useReportTimezone() {
  const { currentAccount } = useAccount();
  return computed(() => {
    const timeZone = currentAccount.value.settings?.reporting_timezone;
    return timeZone && isKnownTimezone(timeZone) ? timeZone : null;
  });
}
