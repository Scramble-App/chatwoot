import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

/**
 * The account's reports timezone, or null when reports follow the browser timezone.
 * @returns {import('vue').ComputedRef<string|null>}
 */
export function useReportTimezone() {
  const { currentAccount } = useAccount();
  return computed(
    () => currentAccount.value.settings?.reporting_timezone || null
  );
}
