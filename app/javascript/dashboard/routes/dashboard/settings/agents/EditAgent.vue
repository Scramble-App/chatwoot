<script setup>
import { ref, computed } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useConfig } from 'dashboard/composables/useConfig';
import Button from 'dashboard/components-next/button/Button.vue';
import Auth from '../../../../api/auth';
import wootConstants from 'dashboard/constants/globals';
import {
  DEFAULT_AGENT_SCHEDULE_TIMEZONE,
  agentScheduleTimezoneOptions,
} from './helpers/timezone';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    default: '',
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
  translationLocale: {
    type: String,
    default: '',
  },
  scheduleEnabled: {
    type: Boolean,
    default: false,
  },
  scheduleTimezone: {
    type: String,
    default: DEFAULT_AGENT_SCHEDULE_TIMEZONE,
  },
  workingHours: {
    type: Array,
    default: () => [],
  },
  scheduleExceptions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const { t } = useI18n();
const { enabledLanguages } = useConfig();

function formatTime(hour = 9, minutes = 0) {
  return `${String(hour).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

function parseTime(value) {
  const [hour, minutes] = value.split(':').map(item => Number(item));
  return { hour, minutes };
}

function formatDateTime(value) {
  if (!value) return '';

  const date = new Date(value);
  const offsetDate = new Date(
    date.getTime() - date.getTimezoneOffset() * 60000
  );
  return offsetDate.toISOString().slice(0, 16);
}

function normalizeDateTime(value) {
  return value ? new Date(value).toISOString() : null;
}

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const selectedRoleId = ref(props.customRoleId || props.type);
const selectedTranslationLocale = ref(props.translationLocale || '');
const scheduleEnabled = ref(props.scheduleEnabled);
const scheduleTimezone = ref(
  props.scheduleTimezone || DEFAULT_AGENT_SCHEDULE_TIMEZONE
);
const workingHours = ref(
  props.workingHours.map(workingHour => ({
    day_of_week: workingHour.day_of_week,
    open_time: formatTime(workingHour.open_hour, workingHour.open_minutes),
    close_time: formatTime(workingHour.close_hour, workingHour.close_minutes),
  }))
);
const scheduleExceptions = ref(
  props.scheduleExceptions.map(scheduleException => ({
    name: scheduleException.name || '',
    starts_at: formatDateTime(scheduleException.starts_at),
    ends_at: formatDateTime(scheduleException.ends_at),
    available: !!scheduleException.available,
  }))
);
const agentCredentials = ref({ email: props.email });

const rules = {
  agentName: { required, minLength: minLength(1) },
  selectedRoleId: { required },
  agentAvailability: { required },
};

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');

const roles = computed(() => {
  const defaultRoles = [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
    },
  ];

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const weekDays = computed(() => [
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.SUNDAY'), value: 0 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.MONDAY'), value: 1 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.TUESDAY'), value: 2 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.WEDNESDAY'), value: 3 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.THURSDAY'), value: 4 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.FRIDAY'), value: 5 },
  { label: t('AGENT_MGMT.SCHEDULE.DAYS.SATURDAY'), value: 6 },
]);

const timezoneOptions = computed(() => agentScheduleTimezoneOptions());

const availabilityStatuses = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    disabled: props.availability === AVAILABILITY_STATUS_KEYS[index],
  }))
);

const languageOptions = computed(() => [
  {
    name: t('AGENT_MGMT.TRANSLATION_LANGUAGE.NONE'),
    iso_639_1_code: '',
  },
  ...(enabledLanguages ?? []),
]);

function addWorkingHour() {
  workingHours.value = [
    ...workingHours.value,
    { day_of_week: 1, open_time: '09:00', close_time: '18:00' },
  ];
}

function removeWorkingHour(index) {
  workingHours.value = workingHours.value.filter(
    (_, itemIndex) => itemIndex !== index
  );
}

function addScheduleException() {
  scheduleExceptions.value = [
    ...scheduleExceptions.value,
    { name: '', starts_at: '', ends_at: '', available: false },
  ];
}

function removeScheduleException(index) {
  scheduleExceptions.value = scheduleExceptions.value.filter(
    (_, itemIndex) => itemIndex !== index
  );
}

function normalizedWorkingHours() {
  return workingHours.value.map(workingHour => {
    const openTime = parseTime(workingHour.open_time);
    const closeTime = parseTime(workingHour.close_time);
    return {
      day_of_week: Number(workingHour.day_of_week),
      open_hour: openTime.hour,
      open_minutes: openTime.minutes,
      close_hour: closeTime.hour,
      close_minutes: closeTime.minutes,
    };
  });
}

function normalizedScheduleExceptions() {
  return scheduleExceptions.value
    .filter(
      scheduleException =>
        scheduleException.starts_at && scheduleException.ends_at
    )
    .map(scheduleException => ({
      name: scheduleException.name,
      starts_at: normalizeDateTime(scheduleException.starts_at),
      ends_at: normalizeDateTime(scheduleException.ends_at),
      available: scheduleException.available,
    }));
}

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      id: props.id,
      name: agentName.value,
      availability: agentAvailability.value,
      translation_locale: selectedTranslationLocale.value || null,
      schedule_enabled: scheduleEnabled.value,
      schedule_timezone:
        scheduleTimezone.value || DEFAULT_AGENT_SCHEDULE_TIMEZONE,
      working_hours: normalizedWorkingHours(),
      schedule_exceptions: normalizedScheduleExceptions(),
    };

    if (scheduleEnabled.value) {
      delete payload.availability;
    }

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
      payload.custom_role_id = null;
    }

    await store.dispatch('agents/update', payload);
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  try {
    await Auth.resetPassword(agentCredentials.value);
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <select
            v-model="agentAvailability"
            :disabled="scheduleEnabled"
            @change="v$.agentAvailability.$touch"
          >
            <option
              v-for="status in availabilityStatuses"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
          <p v-if="scheduleEnabled" class="text-body-mini text-n-slate-11 mt-1">
            {{ $t('AGENT_MGMT.SCHEDULE.STATUS_READ_ONLY') }}
          </p>
        </label>
      </div>

      <div class="w-full flex items-center gap-2">
        <input v-model="scheduleEnabled" type="checkbox" :value="true" />
        <label for="agent_schedule_enabled">
          {{ $t('AGENT_MGMT.SCHEDULE.ENABLED') }}
        </label>
      </div>

      <div v-if="scheduleEnabled" class="w-full flex flex-col gap-3">
        <label>
          {{ $t('AGENT_MGMT.SCHEDULE.TIMEZONE') }}
          <select
            v-model="scheduleTimezone"
            data-test-id="agent-schedule-timezone-select"
          >
            <option
              v-for="timezone in timezoneOptions"
              :key="timezone.value"
              :value="timezone.value"
            >
              {{ timezone.label }}
            </option>
          </select>
        </label>

        <div class="flex items-center justify-between">
          <h3 class="text-heading-3 text-n-slate-12 mb-0">
            {{ $t('AGENT_MGMT.SCHEDULE.WEEKLY_HOURS') }}
          </h3>
          <Button
            ghost
            type="button"
            icon="i-lucide-plus"
            :label="$t('AGENT_MGMT.SCHEDULE.ADD_INTERVAL')"
            @click.prevent="addWorkingHour"
          />
        </div>

        <div
          v-for="(workingHour, index) in workingHours"
          :key="`working-hour-${index}`"
          class="grid grid-cols-12 gap-2 items-end"
        >
          <label class="col-span-4">
            {{ $t('AGENT_MGMT.SCHEDULE.DAY') }}
            <select v-model="workingHour.day_of_week">
              <option
                v-for="day in weekDays"
                :key="day.value"
                :value="day.value"
              >
                {{ day.label }}
              </option>
            </select>
          </label>
          <label class="col-span-3">
            {{ $t('AGENT_MGMT.SCHEDULE.START') }}
            <input v-model="workingHour.open_time" type="time" />
          </label>
          <label class="col-span-3">
            {{ $t('AGENT_MGMT.SCHEDULE.END') }}
            <input v-model="workingHour.close_time" type="time" />
          </label>
          <div class="col-span-2 pb-1">
            <Button
              ghost
              type="button"
              icon="i-lucide-trash"
              :label="$t('AGENT_MGMT.SCHEDULE.REMOVE')"
              @click.prevent="removeWorkingHour(index)"
            />
          </div>
        </div>

        <div class="flex items-center justify-between">
          <h3 class="text-heading-3 text-n-slate-12 mb-0">
            {{ $t('AGENT_MGMT.SCHEDULE.EXCEPTIONS') }}
          </h3>
          <Button
            ghost
            type="button"
            icon="i-lucide-plus"
            :label="$t('AGENT_MGMT.SCHEDULE.ADD_EXCEPTION')"
            @click.prevent="addScheduleException"
          />
        </div>

        <div
          v-for="(scheduleException, index) in scheduleExceptions"
          :key="`schedule-exception-${index}`"
          class="grid grid-cols-12 gap-2 items-end"
        >
          <label class="col-span-3">
            {{ $t('AGENT_MGMT.SCHEDULE.EXCEPTION_NAME') }}
            <input v-model="scheduleException.name" type="text" />
          </label>
          <label class="col-span-3">
            {{ $t('AGENT_MGMT.SCHEDULE.START') }}
            <input
              v-model="scheduleException.starts_at"
              type="datetime-local"
            />
          </label>
          <label class="col-span-3">
            {{ $t('AGENT_MGMT.SCHEDULE.END') }}
            <input v-model="scheduleException.ends_at" type="datetime-local" />
          </label>
          <label class="col-span-1 flex items-center gap-2 pb-2">
            <input v-model="scheduleException.available" type="checkbox" />
            {{ $t('AGENT_MGMT.SCHEDULE.AVAILABLE') }}
          </label>
          <div class="col-span-2 pb-1">
            <Button
              ghost
              type="button"
              icon="i-lucide-trash"
              :label="$t('AGENT_MGMT.SCHEDULE.REMOVE')"
              @click.prevent="removeScheduleException(index)"
            />
          </div>
        </div>
      </div>

      <div class="w-full">
        <label>
          {{ $t('AGENT_MGMT.TRANSLATION_LANGUAGE.LABEL') }}
          <select v-model="selectedTranslationLocale">
            <option
              v-for="language in languageOptions"
              :key="language.iso_639_1_code || 'none'"
              :value="language.iso_639_1_code"
            >
              {{ language.name }}
            </option>
          </select>
        </label>
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right">
          <Button
            v-if="provider !== 'saml'"
            ghost
            type="button"
            icon="i-lucide-lock-keyhole"
            class="!px-2"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_RESET_BUTTON')"
            @click.prevent="resetPassword"
          />
        </div>
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="v$.$invalid || uiFlags.isUpdating"
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
