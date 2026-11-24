<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  botId: { type: Number, required: true },
});

const emit = defineEmits(['imported']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const fileInputRef = ref(null);
const file = ref(null);
const preview = ref(null);
const errorMessage = ref('');
const isRunning = ref(false);

// Every open() starts a session and keeps the bot it was opened for, so a
// check that ends after the dialog was reopened is dropped and the import
// always goes to the bot whose file was checked
let session = 0;
let openedBotId = null;

const rowErrors = computed(() => preview.value?.errors || []);
const hasChanges = computed(
  () => preview.value && preview.value.created + preview.value.updated > 0
);
const canImport = computed(() => hasChanges.value && !rowErrors.value.length);

const importFile = dryRun =>
  store.dispatch('aiAgentKnowledge/importEntries', {
    botId: openedBotId,
    file: file.value,
    dryRun,
  });

// An import with invalid rows is refused with a 422 that lists them
const showFailure = (error, fallbackMessage) => {
  const data = error.response?.data || {};
  if (Array.isArray(data.errors) && data.errors.length) {
    preview.value = {
      created: 0,
      updated: 0,
      ...preview.value,
      errors: data.errors,
    };
  } else {
    errorMessage.value = data.error || data.message || fallbackMessage;
  }
};

const checkFile = async () => {
  const checkSession = session;
  isRunning.value = true;
  try {
    const result = await importFile(true);
    if (checkSession === session) preview.value = result;
  } catch (error) {
    if (checkSession === session) {
      showFailure(error, t('AI_AGENT.KNOWLEDGE.IMPORT.CHECK_ERROR'));
    }
  } finally {
    if (checkSession === session) isRunning.value = false;
  }
};

const chooseFile = () => fileInputRef.value.click();

const onFileChange = async event => {
  const [selected] = event.target.files;
  // Lets the same file be picked again after it was fixed
  event.target.value = '';
  if (!selected) return;

  file.value = selected;
  preview.value = null;
  errorMessage.value = '';
  await checkFile();
};

const applyImport = async () => {
  const applySession = session;
  errorMessage.value = '';
  isRunning.value = true;
  try {
    const result = await importFile(false);
    // The import is saved even if the dialog was closed meanwhile
    useAlert(
      t('AI_AGENT.KNOWLEDGE.IMPORT.SUCCESS', {
        created: result.created,
        updated: result.updated,
      })
    );
    emit('imported');
    if (applySession === session) dialogRef.value.close();
  } catch (error) {
    if (applySession === session) {
      showFailure(error, t('AI_AGENT.KNOWLEDGE.IMPORT.APPLY_ERROR'));
    }
  } finally {
    if (applySession === session) isRunning.value = false;
  }
};

const open = () => {
  session += 1;
  openedBotId = props.botId;
  file.value = null;
  preview.value = null;
  errorMessage.value = '';
  isRunning.value = false;
  dialogRef.value.open();
};

onBeforeUnmount(() => {
  session += 1;
});

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AI_AGENT.KNOWLEDGE.IMPORT.TITLE')"
    :description="t('AI_AGENT.KNOWLEDGE.IMPORT.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENT.KNOWLEDGE.IMPORT.CONFIRM')"
    :disable-confirm-button="!canImport"
    :is-loading="isRunning && !!preview"
    overflow-y-auto
    @confirm="applyImport"
  >
    <div class="flex flex-col gap-4">
      <input
        ref="fileInputRef"
        type="file"
        accept=".csv,text/csv"
        class="hidden"
        @change="onFileChange"
      />
      <div class="flex flex-wrap items-center gap-3">
        <Button
          type="button"
          :label="
            file
              ? t('AI_AGENT.KNOWLEDGE.IMPORT.CHOOSE_ANOTHER')
              : t('AI_AGENT.KNOWLEDGE.IMPORT.CHOOSE_FILE')
          "
          icon="i-lucide-file-up"
          variant="faded"
          color="slate"
          size="sm"
          :disabled="isRunning"
          @click="chooseFile"
        />
        <span v-if="file" class="min-w-0 text-sm truncate text-n-slate-11">
          {{ file.name }}
        </span>
      </div>
      <p
        v-if="isRunning && !preview"
        class="flex items-center gap-2 mb-0 text-sm text-n-slate-11"
      >
        <Spinner :size="16" />
        {{ t('AI_AGENT.KNOWLEDGE.IMPORT.CHECKING') }}
      </p>
      <p
        v-if="errorMessage"
        role="alert"
        class="mb-0 text-sm break-words text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>
      <template v-if="preview">
        <div class="grid grid-cols-2 gap-3">
          <div class="flex flex-col px-3 py-2 rounded-lg bg-n-alpha-1">
            <span class="text-xs text-n-slate-11">
              {{ t('AI_AGENT.KNOWLEDGE.IMPORT.CREATED') }}
            </span>
            <span class="text-lg font-medium tabular-nums text-n-slate-12">
              {{ preview.created }}
            </span>
          </div>
          <div class="flex flex-col px-3 py-2 rounded-lg bg-n-alpha-1">
            <span class="text-xs text-n-slate-11">
              {{ t('AI_AGENT.KNOWLEDGE.IMPORT.UPDATED') }}
            </span>
            <span class="text-lg font-medium tabular-nums text-n-slate-12">
              {{ preview.updated }}
            </span>
          </div>
        </div>
        <div v-if="rowErrors.length" class="flex flex-col gap-2">
          <p class="mb-0 text-sm font-medium text-n-ruby-11">
            {{
              t(
                'AI_AGENT.KNOWLEDGE.IMPORT.ERRORS_TITLE',
                { count: rowErrors.length },
                rowErrors.length
              )
            }}
          </p>
          <ul
            class="flex flex-col gap-1 p-0 m-0 overflow-y-auto list-none max-h-60"
          >
            <li
              v-for="(rowError, index) in rowErrors"
              :key="index"
              class="text-sm break-words text-n-slate-12"
            >
              {{
                rowError.row
                  ? t('AI_AGENT.KNOWLEDGE.IMPORT.ROW_ERROR', {
                      row: rowError.row,
                      message: rowError.message,
                    })
                  : rowError.message
              }}
            </li>
          </ul>
        </div>
        <p v-else-if="!hasChanges" class="mb-0 text-sm text-n-slate-11">
          {{ t('AI_AGENT.KNOWLEDGE.IMPORT.NO_CHANGES') }}
        </p>
      </template>
    </div>
  </Dialog>
</template>
