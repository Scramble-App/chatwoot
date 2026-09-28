<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ConversationApi from 'dashboard/api/inbox/conversation';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationId: { type: Number, default: null },
});

// Recording formats that OpenAI accepts; Safari may only offer mp4
const RECORDING_MIME_TYPES = ['audio/webm;codecs=opus', 'audio/mp4'];
// Keeps a recording far below the 25 MB OpenAI upload limit
const MAX_RECORDING_MS = 2 * 60 * 1000;

const { t } = useI18n();

const isRecording = ref(false);
const isTranscribing = ref(false);
let recorder = null;
let stopTimer = null;

const tooltip = computed(() => {
  if (isTranscribing.value) {
    return t('CONVERSATION.REPLYBOX.DICTATION.TRANSCRIBING');
  }
  if (isRecording.value) return t('CONVERSATION.REPLYBOX.DICTATION.STOP');
  return t('CONVERSATION.REPLYBOX.DICTATION.START');
});

const releaseMicrophone = () => {
  clearTimeout(stopTimer);
  recorder.stream.getTracks().forEach(track => track.stop());
};

const transcribe = async audio => {
  isTranscribing.value = true;
  try {
    const { data } = await ConversationApi.transcribeDictation({
      conversationId: props.conversationId,
      audio,
      fileName: `dictation.${audio.type.includes('mp4') ? 'mp4' : 'webm'}`,
    });
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, data.text);
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('CONVERSATION.REPLYBOX.DICTATION.ERROR')
    );
  } finally {
    isTranscribing.value = false;
  }
};

const stopRecording = () => {
  isRecording.value = false;
  recorder.stop();
};

const startRecording = async () => {
  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mimeType = RECORDING_MIME_TYPES.find(type =>
      MediaRecorder.isTypeSupported(type)
    );
    recorder = new MediaRecorder(stream, mimeType ? { mimeType } : {});
  } catch {
    stream?.getTracks().forEach(track => track.stop());
    useAlert(t('CONVERSATION.REPLYBOX.DICTATION.MICROPHONE_ERROR'));
    return;
  }

  const chunks = [];
  recorder.ondataavailable = event => chunks.push(event.data);
  recorder.onstop = () => {
    releaseMicrophone();
    transcribe(new Blob(chunks, { type: recorder.mimeType }));
  };
  recorder.start();
  isRecording.value = true;
  stopTimer = setTimeout(stopRecording, MAX_RECORDING_MS);
};

// Drops a recording that is no longer wanted, e.g. after switching to another conversation
const cancelRecording = () => {
  if (!isRecording.value) return;

  recorder.onstop = releaseMicrophone;
  stopRecording();
};

const toggleRecording = () =>
  isRecording.value ? stopRecording() : startRecording();

watch(() => props.conversationId, cancelRecording);

onBeforeUnmount(cancelRecording);
</script>

<template>
  <NextButton
    v-tooltip.top-end="tooltip"
    :icon="isRecording ? 'i-ph-stop-fill' : 'i-ph-microphone'"
    :color="isRecording ? 'ruby' : 'slate'"
    faded
    sm
    :is-loading="isTranscribing"
    :disabled="isTranscribing"
    :class="{ 'animate-pulse': isRecording }"
    @click="toggleRecording"
  />
</template>
