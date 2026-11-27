<script setup>
import { onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  botId: { type: Number, required: true },
});

const emit = defineEmits(['deleted']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const entry = ref(null);
const isDeleting = ref(false);

// Every open() starts a session and keeps the bot it was opened for, so a
// late response never closes a reopened dialog
let session = 0;
let openedBotId = null;

const open = selected => {
  session += 1;
  openedBotId = props.botId;
  entry.value = selected;
  isDeleting.value = false;
  dialogRef.value.open();
};

const deleteEntry = async () => {
  const deleteSession = session;
  isDeleting.value = true;
  try {
    await store.dispatch('aiAgentKnowledge/deleteEntry', {
      botId: openedBotId,
      id: entry.value.id,
    });
    // The entry is gone even if the dialog was closed meanwhile
    useAlert(t('AI_AGENT.KNOWLEDGE.DELETE.SUCCESS'));
    emit('deleted');
    if (deleteSession === session) dialogRef.value.close();
  } catch (error) {
    if (deleteSession === session) {
      useAlert(t('AI_AGENT.KNOWLEDGE.DELETE.ERROR'));
    }
  } finally {
    if (deleteSession === session) isDeleting.value = false;
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
    type="alert"
    :title="t('AI_AGENT.KNOWLEDGE.DELETE.TITLE', { key: entry?.key })"
    :description="t('AI_AGENT.KNOWLEDGE.DELETE.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENT.KNOWLEDGE.DELETE.CONFIRM')"
    :is-loading="isDeleting"
    @confirm="deleteEntry"
  />
</template>
