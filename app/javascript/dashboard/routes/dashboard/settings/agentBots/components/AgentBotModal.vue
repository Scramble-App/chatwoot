<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  required,
  helpers,
  url,
  integer,
  between,
} from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useToggle } from '@vueuse/core';
import AgentBotsAPI from 'dashboard/api/agentBots';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AccessToken from 'dashboard/routes/dashboard/settings/profile/AccessToken.vue';
import AiAgentTextSetting from './AiAgentTextSetting.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  selectedBot: {
    type: Object,
    default: () => ({}),
  },
});

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const BOT_TYPES = {
  WEBHOOK: 'webhook',
  AI_AGENT: 'ai_agent',
};

// Length limits of the AI agent settings, as the backend validates them
const TEXT_LIMITS = {
  toneOfVoice: 5000,
  instructions: 10000,
  fallbackMessage: 1000,
};

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);
const uiFlags = useMapGetter('agentBots/getUIFlags');
const teams = useMapGetter('teams/getTeams');

const aiAgentStateFrom = (config = {}) => ({
  model: config.model || '',
  reasoningEffort: config.reasoning_effort || '',
  toneOfVoice: config.tone_of_voice || '',
  instructions: config.instructions || '',
  handoffTeamId: config.handoff_team_id ? Number(config.handoff_team_id) : '',
  maxReplies: config.max_replies_per_conversation ?? '',
  fallbackMessage: config.fallback_message || '',
});

const formState = reactive({
  botName: '',
  botDescription: '',
  botType: BOT_TYPES.WEBHOOK,
  botUrl: '',
  botAvatar: null,
  botAvatarUrl: '',
  ...aiAgentStateFrom(),
});

const [showAccessToken, toggleAccessToken] = useToggle();
const accessToken = ref('');
const botSecret = ref('');
const aiAgentDefaults = ref(null);
const teamsLoaded = ref(false);

const isAiAgent = computed(() => formState.botType === BOT_TYPES.AI_AGENT);

const rules = computed(() => {
  const botName = {
    required: helpers.withMessage(
      () => t('AGENT_BOTS.FORM.ERRORS.NAME'),
      required
    ),
  };

  if (isAiAgent.value) {
    const replyLimitError = () =>
      t('AGENT_BOTS.FORM.AI_AGENT.REPLY_LIMIT.ERROR');
    return {
      botName,
      maxReplies: {
        integer: helpers.withMessage(replyLimitError, integer),
        between: helpers.withMessage(replyLimitError, between(1, 200)),
      },
    };
  }

  return {
    botName,
    botUrl: {
      required: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.URL'),
        required
      ),
      url: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.VALID_URL'),
        url
      ),
    },
  };
});

const v$ = useVuelidate(rules, formState);

const isLoading = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? uiFlags.value.isCreating
    : uiFlags.value.isUpdating
);

const dialogTitle = computed(() => {
  if (showAccessToken.value) {
    return t('AGENT_BOTS.ACCESS_TOKEN.TITLE');
  }

  return props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.ADD.TITLE')
    : t('AGENT_BOTS.EDIT.TITLE');
});

const dialogDescription = computed(() => {
  if (showAccessToken.value) {
    return t('AGENT_BOTS.ACCESS_TOKEN.DESCRIPTION');
  }
  return '';
});

const confirmButtonLabel = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.FORM.CREATE')
    : t('AGENT_BOTS.FORM.UPDATE')
);

const botNameError = computed(() =>
  v$.value.botName.$error ? v$.value.botName.$errors[0]?.$message : ''
);

const botUrlError = computed(() =>
  v$.value.botUrl?.$error ? v$.value.botUrl.$errors[0]?.$message : ''
);

const maxRepliesError = computed(() =>
  v$.value.maxReplies?.$error ? v$.value.maxReplies.$errors[0]?.$message : ''
);

const showAccessTokenInput = computed(
  () =>
    showAccessToken.value ||
    props.type === MODAL_TYPES.EDIT ||
    accessToken.value
);

const botTypeOptions = computed(() => [
  {
    value: BOT_TYPES.WEBHOOK,
    label: t('AGENT_BOTS.TYPES.WEBHOOK'),
    description: t('AGENT_BOTS.FORM.TYPE.WEBHOOK_DESCRIPTION'),
  },
  {
    value: BOT_TYPES.AI_AGENT,
    label: t('AGENT_BOTS.TYPES.AI_AGENT'),
    description: t('AGENT_BOTS.FORM.TYPE.AI_AGENT_DESCRIPTION'),
  },
]);

const teamOptions = computed(() => [
  { value: '', label: t('AGENT_BOTS.FORM.AI_AGENT.HANDOFF_TEAM.NONE') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const modelPlaceholder = computed(
  () =>
    aiAgentDefaults.value?.model ||
    t('AGENT_BOTS.FORM.AI_AGENT.MODEL.PLACEHOLDER')
);

const replyLimitPlaceholder = computed(() =>
  String(aiAgentDefaults.value?.max_replies_per_conversation ?? '')
);

const defaultTexts = computed(() => ({
  toneOfVoice: aiAgentDefaults.value?.tone_of_voice || '',
  instructions: aiAgentDefaults.value?.instructions || '',
  fallbackMessage: aiAgentDefaults.value?.fallback_message || '',
}));

const loadTeams = async () => {
  try {
    await store.dispatch('teams/get');
    teamsLoaded.value = true;
  } catch (error) {
    // Without the team list a saved team can't be checked, so it is kept
  }
};

const loadDefaults = async () => {
  try {
    const { data } = await AgentBotsAPI.getAiAgentDefaults();
    aiAgentDefaults.value = data;
  } catch (error) {
    // Without defaults the fields show hints; the next switch to AI agent retries
  }
};

const loadAiAgentOptions = () => {
  if (!teamsLoaded.value) loadTeams();
  if (!aiAgentDefaults.value) loadDefaults();
};

// A blank text means "use the default", and so does the default text itself:
// it is not saved as an override, so a later change of the default applies.
const textSetting = (value, defaultText) => {
  const text = value.trim();
  return text === defaultText.trim() ? '' : text;
};

// Every setting is sent: a blank one goes as an empty string (null for the team
// and the reply limit), so clearing a field brings its default back.
const aiAgentConfig = () => ({
  model: formState.model.trim(),
  reasoning_effort: formState.reasoningEffort,
  tone_of_voice: textSetting(
    formState.toneOfVoice,
    defaultTexts.value.toneOfVoice
  ),
  instructions: textSetting(
    formState.instructions,
    defaultTexts.value.instructions
  ),
  handoff_team_id: formState.handoffTeamId || null,
  max_replies_per_conversation:
    formState.maxReplies === '' ? null : Number(formState.maxReplies),
  fallback_message: textSetting(
    formState.fallbackMessage,
    defaultTexts.value.fallbackMessage
  ),
});

const resetForm = () => {
  Object.assign(formState, {
    botName: '',
    botDescription: '',
    botType: BOT_TYPES.WEBHOOK,
    botUrl: '',
    botAvatar: null,
    botAvatarUrl: '',
    ...aiAgentStateFrom(),
  });
  v$.value.$reset();
};

const handleImageUpload = ({ file, url: avatarUrl }) => {
  formState.botAvatar = file;
  formState.botAvatarUrl = avatarUrl;
};

const handleAvatarDelete = async () => {
  if (props.selectedBot?.id) {
    try {
      await store.dispatch(
        'agentBots/deleteAgentBotAvatar',
        props.selectedBot.id
      );
      formState.botAvatar = null;
      formState.botAvatarUrl = '';
      useAlert(t('AGENT_BOTS.AVATAR.SUCCESS_DELETE'));
    } catch (error) {
      useAlert(t('AGENT_BOTS.AVATAR.ERROR_DELETE'));
    }
  } else {
    formState.botAvatar = null;
    formState.botAvatarUrl = '';
  }
};

const handleSubmit = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  if (showAccessToken.value) return;

  const botData = {
    name: formState.botName,
    description: formState.botDescription,
    outgoing_url: isAiAgent.value ? '' : formState.botUrl,
    bot_type: formState.botType,
    avatar: formState.botAvatar,
    ...(isAiAgent.value && { bot_config: aiAgentConfig() }),
  };

  const isCreate = props.type === MODAL_TYPES.CREATE;

  try {
    const actionPayload = isCreate
      ? botData
      : { id: props.selectedBot.id, data: botData };

    const response = await store.dispatch(
      `agentBots/${isCreate ? 'create' : 'update'}`,
      actionPayload
    );

    const alertKey = isCreate
      ? t('AGENT_BOTS.ADD.API.SUCCESS_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.SUCCESS_MESSAGE');
    useAlert(alertKey);

    // Show access token and secret after creating a webhook bot
    if (isCreate && !isAiAgent.value) {
      const {
        access_token: responseAccessToken,
        secret: responseSecret,
        id,
      } = response || {};

      if (id && responseAccessToken) {
        accessToken.value = responseAccessToken;
        botSecret.value = responseSecret || '';
        toggleAccessToken(true);
      } else {
        accessToken.value = '';
        botSecret.value = '';
        dialogRef.value.close();
      }
    } else {
      dialogRef.value.close();
    }

    resetForm();
  } catch (error) {
    const errorKey = isCreate
      ? t('AGENT_BOTS.ADD.API.ERROR_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.ERROR_MESSAGE');
    // The store passes the API's validation message through
    useAlert(error?.message || errorKey);
  }
};

const initializeForm = () => {
  if (props.selectedBot && Object.keys(props.selectedBot).length) {
    const {
      name,
      description,
      bot_type: botType,
      outgoing_url: botUrl,
      thumbnail,
      bot_config: botConfig,
      access_token: botAccessToken,
      secret: botSecretValue,
    } = props.selectedBot;
    formState.botName = name || '';
    formState.botDescription = description || '';
    formState.botType = botType || BOT_TYPES.WEBHOOK;
    formState.botUrl = botUrl || botConfig?.webhook_url || '';
    formState.botAvatarUrl = thumbnail || '';
    Object.assign(formState, aiAgentStateFrom(botConfig || {}));

    if (props.type === MODAL_TYPES.EDIT) {
      if (botAccessToken) accessToken.value = botAccessToken;
      if (botSecretValue) botSecret.value = botSecretValue;
    }
  } else {
    resetForm();
  }
};

const onCopyToken = async value => {
  await copyTextToClipboard(value);
  useAlert(t('AGENT_BOTS.ACCESS_TOKEN.COPY_SUCCESSFUL'));
};

const onCopySecret = async value => {
  await copyTextToClipboard(value || botSecret.value);
  useAlert(t('AGENT_BOTS.SECRET.COPY_SUCCESS'));
};

const onResetSecret = async () => {
  const response = await store.dispatch(
    'agentBots/resetSecret',
    props.selectedBot.id
  );
  if (response) {
    botSecret.value = response.secret;
    useAlert(t('AGENT_BOTS.SECRET.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.SECRET.RESET_ERROR'));
  }
};

const onResetToken = async () => {
  const response = await store.dispatch(
    'agentBots/resetAccessToken',
    props.selectedBot.id
  );
  if (response) {
    accessToken.value = response.access_token;
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_ERROR'));
  }
};

const closeModal = () => {
  if (!showAccessToken.value) v$.value?.$reset();
  accessToken.value = '';
  botSecret.value = '';
  toggleAccessToken(false);
  // Unsaved edits are dropped, so the next open shows the bot as saved
  initializeForm();
};

const onClickClose = () => {
  closeModal();
  dialogRef.value.close();
};

watch(() => props.selectedBot, initializeForm, { immediate: true, deep: true });

watch(
  isAiAgent,
  value => {
    if (value) loadAiAgentOptions();
  },
  { immediate: true }
);

// A saved team that was deleted would fail every save; once the teams are
// loaded, it becomes None.
watch(
  () => [teamsLoaded.value, teams.value, formState.handoffTeamId],
  () => {
    if (!teamsLoaded.value || !formState.handoffTeamId) return;
    if (!teams.value.some(team => team.id === formState.handoffTeamId)) {
      formState.handoffTeamId = '';
    }
  }
);

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    overflow-y-auto
    :title="dialogTitle"
    :description="dialogDescription"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="closeModal"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <div
        v-if="!showAccessToken || type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-4"
      >
        <div class="mb-2 flex flex-col items-start">
          <span class="mb-2 text-sm font-medium text-n-slate-12">
            {{ $t('AGENT_BOTS.FORM.AVATAR.LABEL') }}
          </span>
          <Avatar
            :src="formState.botAvatarUrl"
            :name="formState.botName"
            :size="68"
            allow-upload
            icon-name="i-lucide-bot-message-square"
            @upload="handleImageUpload"
            @delete="handleAvatarDelete"
          />
        </div>

        <Input
          id="bot-name"
          v-model="formState.botName"
          :label="$t('AGENT_BOTS.FORM.NAME.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.NAME.PLACEHOLDER')"
          :message="botNameError"
          :message-type="botNameError ? 'error' : 'info'"
          @blur="v$.botName.$touch()"
        />

        <TextArea
          id="bot-description"
          v-model="formState.botDescription"
          :label="$t('AGENT_BOTS.FORM.DESCRIPTION.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.DESCRIPTION.PLACEHOLDER')"
        />

        <div class="flex flex-col gap-2">
          <span
            id="agent-bot-type-label"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ $t('AGENT_BOTS.FORM.TYPE.LABEL') }}
          </span>
          <div
            role="radiogroup"
            aria-labelledby="agent-bot-type-label"
            class="grid grid-cols-1 gap-3 sm:grid-cols-2"
          >
            <label
              v-for="option in botTypeOptions"
              :key="option.value"
              class="flex flex-col gap-2 p-4 cursor-pointer rounded-xl outline outline-1 bg-n-solid-1 transition-all duration-200"
              :class="
                formState.botType === option.value
                  ? 'outline-n-blue-9'
                  : 'outline-n-weak hover:outline-n-strong'
              "
            >
              <span class="flex items-center justify-between w-full gap-3">
                <span
                  :id="`agent-bot-type-${option.value}-label`"
                  class="text-heading-3 text-n-slate-12"
                >
                  {{ option.label }}
                </span>
                <input
                  :id="`agent-bot-type-${option.value}`"
                  v-model="formState.botType"
                  type="radio"
                  name="agent-bot-type"
                  class="flex-shrink-0 size-4 accent-n-blue-9"
                  :value="option.value"
                  :aria-labelledby="`agent-bot-type-${option.value}-label`"
                  :aria-describedby="`agent-bot-type-${option.value}-description`"
                />
              </span>
              <span
                :id="`agent-bot-type-${option.value}-description`"
                class="text-body-main text-n-slate-11"
              >
                {{ option.description }}
              </span>
            </label>
          </div>
        </div>

        <Input
          v-if="!isAiAgent"
          id="bot-url"
          v-model="formState.botUrl"
          :label="$t('AGENT_BOTS.FORM.WEBHOOK_URL.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.WEBHOOK_URL.PLACEHOLDER')"
          :message="botUrlError"
          :message-type="botUrlError ? 'error' : 'info'"
          @blur="v$.botUrl.$touch()"
        />

        <template v-else>
          <div class="flex flex-col gap-1">
            <Input
              id="bot-model"
              v-model="formState.model"
              maxlength="255"
              :label="$t('AGENT_BOTS.FORM.AI_AGENT.MODEL.LABEL')"
              :placeholder="modelPlaceholder"
            />
            <p class="mb-0 text-label-small text-n-slate-11">
              {{ $t('AGENT_BOTS.FORM.AI_AGENT.MODEL.HELP') }}
            </p>
          </div>

          <AiAgentTextSetting
            id="bot-tone-of-voice"
            v-model="formState.toneOfVoice"
            :label="$t('AGENT_BOTS.FORM.AI_AGENT.TONE_OF_VOICE.LABEL')"
            :help="$t('AGENT_BOTS.FORM.AI_AGENT.DEFAULT_TEXT_HELP')"
            :default-text="defaultTexts.toneOfVoice"
            :max-length="TEXT_LIMITS.toneOfVoice"
            min-height="6rem"
            max-height="16rem"
          />

          <AiAgentTextSetting
            id="bot-instructions"
            v-model="formState.instructions"
            :label="$t('AGENT_BOTS.FORM.AI_AGENT.INSTRUCTIONS.LABEL')"
            :help="$t('AGENT_BOTS.FORM.AI_AGENT.DEFAULT_TEXT_HELP')"
            :default-text="defaultTexts.instructions"
            :max-length="TEXT_LIMITS.instructions"
            min-height="8rem"
            max-height="20rem"
          />

          <div class="flex flex-col gap-1">
            <label class="flex flex-col gap-1">
              {{ $t('AGENT_BOTS.FORM.AI_AGENT.HANDOFF_TEAM.LABEL') }}
              <Select
                v-model="formState.handoffTeamId"
                :options="teamOptions"
                class="!w-full font-normal"
                data-test-id="bot-handoff-team"
              />
            </label>
            <p class="mb-0 text-label-small text-n-slate-11">
              {{ $t('AGENT_BOTS.FORM.AI_AGENT.HANDOFF_TEAM.HELP') }}
            </p>
          </div>

          <div class="flex flex-col gap-1">
            <Input
              id="bot-reply-limit"
              v-model="formState.maxReplies"
              type="number"
              max="200"
              :label="$t('AGENT_BOTS.FORM.AI_AGENT.REPLY_LIMIT.LABEL')"
              :placeholder="replyLimitPlaceholder"
              :message="maxRepliesError"
              :message-type="maxRepliesError ? 'error' : 'info'"
              @blur="v$.maxReplies.$touch()"
            />
            <p class="mb-0 text-label-small text-n-slate-11">
              {{ $t('AGENT_BOTS.FORM.AI_AGENT.REPLY_LIMIT.HELP') }}
            </p>
          </div>

          <AiAgentTextSetting
            id="bot-fallback-message"
            v-model="formState.fallbackMessage"
            :label="$t('AGENT_BOTS.FORM.AI_AGENT.FALLBACK_MESSAGE.LABEL')"
            :help="$t('AGENT_BOTS.FORM.AI_AGENT.FALLBACK_MESSAGE.HELP')"
            :default-text="defaultTexts.fallbackMessage"
            :max-length="TEXT_LIMITS.fallbackMessage"
          />
        </template>
      </div>

      <div
        v-if="botSecret && type === MODAL_TYPES.EDIT && !isAiAgent"
        class="flex flex-col gap-1"
      >
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          @on-copy="onCopySecret"
          @on-reset="onResetSecret"
        />
      </div>

      <div v-if="showAccessTokenInput" class="flex flex-col gap-1">
        <label
          v-if="type === MODAL_TYPES.EDIT"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ $t('AGENT_BOTS.ACCESS_TOKEN.TITLE') }}
        </label>
        <AccessToken
          v-if="type === MODAL_TYPES.EDIT"
          :value="accessToken"
          @on-copy="onCopyToken"
          @on-reset="onResetToken"
        />
        <AccessToken
          v-else
          :value="accessToken"
          :show-reset-button="false"
          @on-copy="onCopyToken"
        />
      </div>

      <div
        v-if="botSecret && showAccessToken && type === MODAL_TYPES.CREATE"
        class="flex flex-col gap-1"
      >
        <p class="text-sm text-n-slate-11">
          {{ $t('AGENT_BOTS.SECRET.CREATED_DESC') }}
        </p>
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          :show-reset-button="false"
          @on-copy="onCopySecret"
        />
      </div>

      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('AGENT_BOTS.FORM.CANCEL')"
          @click="onClickClose()"
        />
        <NextButton
          v-if="!showAccessToken"
          type="submit"
          data-testid="label-submit"
          :label="confirmButtonLabel"
          :is-loading="isLoading"
          :disabled="v$.$invalid"
        />
      </div>
    </form>
  </Dialog>
</template>
