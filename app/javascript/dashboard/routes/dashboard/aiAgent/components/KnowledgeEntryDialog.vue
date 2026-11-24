<script setup>
import { computed, onBeforeUnmount, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useStatusOptions } from '../useStatusOptions';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  botId: { type: Number, required: true },
  categories: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

const TEXT_FIELDS = [
  'key',
  'category',
  'frequency',
  'question',
  'alternative_questions',
  'short_answer',
  'answer',
  'selling_point',
];

const buildForm = (entry = {}) => ({
  ...Object.fromEntries(TEXT_FIELDS.map(field => [field, entry[field] || ''])),
  status: entry.status || 'draft',
});

// One phrasing per line, without blank lines or stray spaces
const normalizeLines = text =>
  text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .join('\n');

const buildPayload = form => ({
  ...Object.fromEntries(TEXT_FIELDS.map(field => [field, form[field].trim()])),
  alternative_questions: normalizeLines(form.alternative_questions),
  status: form.status,
});

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { statusOptions } = useStatusOptions();

const dialogRef = ref(null);
const entry = ref(null);
const form = reactive(buildForm());
const questions = ref([]);
const errorMessage = ref('');
const errorAttributes = ref([]);
const isSaving = ref(false);

// Every open() starts a session and keeps the bot it was opened for, so a
// late response never changes a reopened dialog and a save never goes to
// another bot
let session = 0;
let openedBotId = null;

const isEditing = computed(() => !!entry.value);

const title = computed(() =>
  isEditing.value
    ? t('AI_AGENT.KNOWLEDGE.FORM.EDIT_TITLE', { key: entry.value.key })
    : t('AI_AGENT.KNOWLEDGE.FORM.CREATE_TITLE')
);

const showPublishHint = computed(
  () =>
    form.status === 'published' &&
    !form.short_answer.trim() &&
    !form.answer.trim()
);

const hasError = field => errorAttributes.value.includes(field);
const messageType = field => (hasError(field) ? 'error' : 'info');

const conversationRoute = conversationId => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: conversationId,
  },
});

const loadQuestions = async id => {
  const loadSession = session;
  try {
    const data = await store.dispatch('aiAgentKnowledge/showEntry', {
      botId: openedBotId,
      id,
    });
    if (loadSession === session) questions.value = data.questions || [];
  } catch (error) {
    // The wordings are extra context, the entry can be edited without them
  }
};

const open = (selected = null) => {
  session += 1;
  openedBotId = props.botId;
  entry.value = selected;
  Object.assign(form, buildForm(selected || {}));
  questions.value = [];
  errorMessage.value = '';
  errorAttributes.value = [];
  isSaving.value = false;
  dialogRef.value.open();
  if (selected) loadQuestions(selected.id);
};

const save = async () => {
  const saveSession = session;
  const isUpdate = isEditing.value;
  errorMessage.value = '';
  errorAttributes.value = [];
  isSaving.value = true;

  try {
    if (isUpdate) {
      await store.dispatch('aiAgentKnowledge/updateEntry', {
        botId: openedBotId,
        id: entry.value.id,
        ...buildPayload(form),
      });
    } else {
      await store.dispatch('aiAgentKnowledge/createEntry', {
        botId: openedBotId,
        ...buildPayload(form),
      });
    }
    // The entry is saved even if the dialog was closed meanwhile
    useAlert(
      isUpdate
        ? t('AI_AGENT.KNOWLEDGE.FORM.UPDATE_SUCCESS')
        : t('AI_AGENT.KNOWLEDGE.FORM.CREATE_SUCCESS')
    );
    emit('saved');
    if (saveSession === session) dialogRef.value.close();
  } catch (error) {
    if (saveSession !== session) return;
    const { message, error: apiError, attributes } = error.response?.data || {};
    errorMessage.value =
      message || apiError || t('AI_AGENT.KNOWLEDGE.FORM.SAVE_ERROR');
    errorAttributes.value = attributes || [];
  } finally {
    if (saveSession === session) isSaving.value = false;
  }
};

onBeforeUnmount(() => {
  session += 1;
});

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    width="2xl"
    position="top"
    overflow-y-auto
    :confirm-button-label="t('AI_AGENT.KNOWLEDGE.FORM.SAVE')"
    :is-loading="isSaving"
    :disable-confirm-button="!form.question.trim()"
    @confirm="save"
  >
    <div class="flex flex-col gap-4">
      <section v-if="questions.length" class="flex flex-col gap-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('AI_AGENT.KNOWLEDGE.FORM.QUESTIONS.TITLE') }}
        </h4>
        <ul
          class="flex flex-col gap-2 p-0 m-0 overflow-y-auto list-none max-h-48"
        >
          <li
            v-for="question in questions"
            :key="question.id"
            class="flex flex-col gap-1 px-3 py-2 rounded-lg bg-n-alpha-1"
          >
            <p class="mb-0 text-sm break-words text-n-slate-12">
              {{ question.content }}
            </p>
            <p class="flex flex-wrap mb-0 text-xs gap-x-2 text-n-slate-11">
              <router-link
                :to="conversationRoute(question.conversation_id)"
                class="text-n-blue-11 hover:underline"
              >
                {{
                  t('AI_AGENT.KNOWLEDGE.FORM.QUESTIONS.OPEN_CONVERSATION', {
                    id: question.conversation_id,
                  })
                }}
              </router-link>
              <span>{{ dynamicTime(question.created_at) }}</span>
            </p>
          </li>
        </ul>
      </section>
      <div class="grid gap-4 sm:grid-cols-2">
        <Input
          v-model="form.key"
          :label="t('AI_AGENT.KNOWLEDGE.FORM.KEY.LABEL')"
          :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.KEY.PLACEHOLDER')"
          :message-type="messageType('key')"
          maxlength="255"
        />
        <Input
          v-model="form.category"
          :label="t('AI_AGENT.KNOWLEDGE.FORM.CATEGORY.LABEL')"
          :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.CATEGORY.PLACEHOLDER')"
          :message-type="messageType('category')"
          list="ai-agent-entry-categories"
          maxlength="255"
        />
        <Input
          v-model="form.frequency"
          :label="t('AI_AGENT.KNOWLEDGE.FORM.FREQUENCY.LABEL')"
          :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.FREQUENCY.PLACEHOLDER')"
          :message-type="messageType('frequency')"
          maxlength="255"
        />
        <label class="flex flex-col gap-1 mb-0">
          <span class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('AI_AGENT.KNOWLEDGE.FORM.STATUS.LABEL') }}
          </span>
          <Select
            v-model="form.status"
            :options="statusOptions"
            :error="hasError('status') ? errorMessage : ''"
          />
        </label>
      </div>
      <datalist id="ai-agent-entry-categories">
        <option v-for="name in categories" :key="name" :value="name" />
      </datalist>
      <TextArea
        id="ai-agent-entry-question"
        v-model="form.question"
        :label="t('AI_AGENT.KNOWLEDGE.FORM.QUESTION.LABEL')"
        :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.QUESTION.PLACEHOLDER')"
        :message-type="messageType('question')"
        auto-height
      />
      <TextArea
        id="ai-agent-entry-alternative-questions"
        v-model="form.alternative_questions"
        :label="t('AI_AGENT.KNOWLEDGE.FORM.ALTERNATIVE_QUESTIONS.LABEL')"
        :placeholder="
          t('AI_AGENT.KNOWLEDGE.FORM.ALTERNATIVE_QUESTIONS.PLACEHOLDER')
        "
        :message-type="messageType('alternative_questions')"
        auto-height
        min-height="5rem"
      />
      <TextArea
        id="ai-agent-entry-short-answer"
        v-model="form.short_answer"
        :label="t('AI_AGENT.KNOWLEDGE.FORM.SHORT_ANSWER.LABEL')"
        :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.SHORT_ANSWER.PLACEHOLDER')"
        :message-type="messageType('short_answer')"
        auto-height
      />
      <TextArea
        id="ai-agent-entry-answer"
        v-model="form.answer"
        :label="t('AI_AGENT.KNOWLEDGE.FORM.ANSWER.LABEL')"
        :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.ANSWER.PLACEHOLDER')"
        :message-type="messageType('answer')"
        auto-height
        min-height="6rem"
        max-height="20rem"
      />
      <TextArea
        id="ai-agent-entry-selling-point"
        v-model="form.selling_point"
        :label="t('AI_AGENT.KNOWLEDGE.FORM.SELLING_POINT.LABEL')"
        :placeholder="t('AI_AGENT.KNOWLEDGE.FORM.SELLING_POINT.PLACEHOLDER')"
        :message-type="messageType('selling_point')"
        auto-height
      />
      <p v-if="showPublishHint" class="mb-0 text-sm text-n-amber-11">
        {{ t('AI_AGENT.KNOWLEDGE.FORM.PUBLISH_HINT') }}
      </p>
      <p
        v-if="errorMessage"
        role="alert"
        class="mb-0 text-sm break-words text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>
    </div>
  </Dialog>
</template>
