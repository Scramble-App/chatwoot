<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  botId: { type: Number, required: true },
});

const emit = defineEmits(['deleted']);

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('aiAgentKnowledge/getUIFlags');

const dialogRef = ref(null);
const entry = ref(null);

const open = selected => {
  entry.value = selected;
  dialogRef.value.open();
};

const deleteEntry = async () => {
  try {
    await store.dispatch('aiAgentKnowledge/deleteEntry', {
      botId: props.botId,
      id: entry.value.id,
    });
    useAlert(t('AI_AGENT.KNOWLEDGE.DELETE.SUCCESS'));
    emit('deleted');
    dialogRef.value.close();
  } catch (error) {
    useAlert(t('AI_AGENT.KNOWLEDGE.DELETE.ERROR'));
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('AI_AGENT.KNOWLEDGE.DELETE.TITLE', { key: entry?.key })"
    :description="t('AI_AGENT.KNOWLEDGE.DELETE.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENT.KNOWLEDGE.DELETE.CONFIRM')"
    :is-loading="uiFlags.isDeleting"
    @confirm="deleteEntry"
  />
</template>
