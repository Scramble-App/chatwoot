<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
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
const uiFlags = useMapGetter('aiAgentKnowledge/getUIFlags');

const dialogRef = ref(null);
const fileInputRef = ref(null);
const file = ref(null);
const preview = ref(null);
const errorMessage = ref('');

const isImporting = computed(() => uiFlags.value.isImporting);
const rowErrors = computed(() => preview.value?.errors || []);
const hasChanges = computed(
  () => preview.value && preview.value.created + preview.value.updated > 0
);
const canImport = computed(() => hasChanges.value && !rowErrors.value.length);

// Row errors come back as a 422 when the file is applied, and may also come
// back that way from a dry run, so both are shown as the preview
const runImport = async dryRun => {
  errorMessage.value = '';
  try {
    return await store.dispatch('aiAgentKnowledge/importEntries', {
      botId: props.botId,
      file: file.value,
      dryRun,
    });
  } catch (error) {
    const data = error.response?.data || {};
    if (Array.isArray(data.errors) && data.errors.length) {
      preview.value = { created: 0, updated: 0, ...data };
    } else {
      preview.value = null;
      errorMessage.value =
        data.error || data.message || t('AI_AGENT.KNOWLEDGE.IMPORT.ERROR');
    }
    return null;
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
  const result = await runImport(true);
  if (result) preview.value = result;
};

const applyImport = async () => {
  const result = await runImport(false);
  if (!result) return;

  useAlert(
    t('AI_AGENT.KNOWLEDGE.IMPORT.SUCCESS', {
      created: result.created,
      updated: result.updated,
    })
  );
  emit('imported');
  dialogRef.value.close();
};

const open = () => {
  file.value = null;
  preview.value = null;
  errorMessage.value = '';
  dialogRef.value.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AI_AGENT.KNOWLEDGE.IMPORT.TITLE')"
    :description="t('AI_AGENT.KNOWLEDGE.IMPORT.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENT.KNOWLEDGE.IMPORT.CONFIRM')"
    :disable-confirm-button="!canImport"
    :is-loading="isImporting && !!preview"
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
          :disabled="isImporting"
          @click="chooseFile"
        />
        <span v-if="file" class="min-w-0 text-sm truncate text-n-slate-11">
          {{ file.name }}
        </span>
      </div>
      <p
        v-if="isImporting && !preview"
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
          {{ t('AI_AGENT.KNOWLEDGE.IMPORT.NOTHING_TO_IMPORT') }}
        </p>
      </template>
    </div>
  </Dialog>
</template>
