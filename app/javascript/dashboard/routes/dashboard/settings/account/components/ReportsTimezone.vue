<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import { agentScheduleTimezoneOptions } from '../../agents/helpers/timezone';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const timezone = ref('');
const timezoneOptions = agentScheduleTimezoneOptions();

watch(
  currentAccount,
  () => {
    timezone.value = currentAccount.value?.settings?.reporting_timezone || '';
  },
  { deep: true, immediate: true }
);

const updateTimezone = async () => {
  try {
    await updateAccount(
      { reporting_timezone: timezone.value || null },
      { silent: true }
    );
    useAlert(t('GENERAL_SETTINGS.FORM.REPORTS_TIMEZONE.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.REPORTS_TIMEZONE.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.REPORTS_TIMEZONE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.REPORTS_TIMEZONE.NOTE')"
    with-border
  >
    <select
      v-model="timezone"
      class="!mb-0 text-sm"
      data-test-id="reports-timezone-select"
      @change="updateTimezone"
    >
      <option value="">
        {{ t('GENERAL_SETTINGS.FORM.REPORTS_TIMEZONE.BROWSER') }}
      </option>
      <option
        v-for="option in timezoneOptions"
        :key="option.value"
        :value="option.value"
      >
        {{ option.label }}
      </option>
    </select>
  </SectionLayout>
</template>
