import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import { useAlert, useTrack } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { CAPTAIN_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { KINDS } from 'dashboard/store/modules/aiGenerations';

// Actions that map to REWRITE events (with operation attribute)
const REWRITE_ACTIONS = [
  'improve',
  'fix_spelling_grammar',
  'casual',
  'professional',
  'expand',
  'shorten',
  'rephrase',
  'make_friendly',
  'make_formal',
  'simplify',
];

const ACTION_KINDS = {
  summarize: KINDS.SUMMARY,
  knowledge_answer: KINDS.KNOWLEDGE_ANSWER,
  prepare_answer: KINDS.PREPARED_REPLY,
};

const KIND_ACTIONS = {
  [KINDS.SUMMARY]: 'summarize',
  [KINDS.KNOWLEDGE_ANSWER]: 'knowledge_answer',
  [KINDS.PREPARED_REPLY]: 'prepare_answer',
};

const IN_PROGRESS_STATUSES = ['pending', 'running'];

/**
 * Gets the event key suffix based on action type.
 * @param {string} action - The action type
 * @returns {string} The event key prefix (REWRITE, SUMMARIZE, or REPLY_SUGGESTION)
 */
function getEventPrefix(action) {
  if (action === 'summarize') return 'SUMMARIZE';
  if (action === 'knowledge_answer') return 'REPLY_SUGGESTION';
  if (action === 'prepare_answer') return 'REPLY_SUGGESTION';
  if (action === 'reply_suggestion') return 'REPLY_SUGGESTION';
  return 'REWRITE';
}

/**
 * Builds the analytics payload based on action type.
 * @param {string} action - The action type
 * @param {number} conversationId - The conversation ID
 * @returns {Object} The payload object
 */
function buildPayload(action, conversationId) {
  const payload = { conversationId };

  if (REWRITE_ACTIONS.includes(action)) {
    payload.operation = action;
  }

  return payload;
}

/**
 * Composable exposing the async AI generation for the selected conversation.
 * State lives in the aiGenerations store module so it survives navigation.
 *
 * @returns {Object} Copilot reply state and methods
 */
export function useCopilotReply() {
  const store = useStore();
  const currentChat = useMapGetter('getSelectedChat');
  const conversationId = computed(() => currentChat.value?.id);

  const isContentReady = ref(false);
  const isEditorDismissed = ref(false);

  const record = computed(() =>
    conversationId.value
      ? store.getters['aiGenerations/active'](conversationId.value)
      : null
  );

  const currentAction = computed(() =>
    record.value ? KIND_ACTIONS[record.value.kind] : null
  );

  const isGenerating = computed(() =>
    IN_PROGRESS_STATUSES.includes(record.value?.status)
  );

  const generatedContent = computed(() =>
    record.value?.status === 'completed' ? record.value.content : ''
  );

  const showEditor = computed(
    () => Boolean(record.value) && !isEditorDismissed.value
  );

  const isActive = computed(() => showEditor.value || isGenerating.value);
  const isButtonDisabled = computed(
    () => isGenerating.value || !isContentReady.value
  );
  const editorTransitionKey = computed(() =>
    isActive.value ? 'copilot' : 'rich'
  );

  const fetchAll = () => {
    if (!conversationId.value) return;

    store.dispatch('aiGenerations/fetchAll', {
      conversationId: conversationId.value,
    });
  };

  watch(conversationId, () => {
    isEditorDismissed.value = false;
    isContentReady.value = false;
    fetchAll();
  });

  onMounted(() => {
    fetchAll();
    emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, fetchAll);
  });

  onUnmounted(() => {
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, fetchAll);
  });

  // A failed generation is surfaced once, then removed so it does not reappear.
  watch(
    () => record.value?.status,
    status => {
      if (status !== 'failed') return;

      useAlert(record.value.error_message);
      store.dispatch('aiGenerations/dismiss', {
        kind: record.value.kind,
        conversationId: record.value.conversationId,
      });
    }
  );

  /**
   * Discards the current suggestion. The stored generation is deleted so it
   * stays dismissed when the operator returns to the conversation.
   * @param {boolean} [trackDismiss=true] - Whether to track dismiss event
   */
  function reset(trackDismiss = true) {
    const current = record.value;

    if (trackDismiss && current?.content && currentAction.value) {
      const eventKey = `${getEventPrefix(currentAction.value)}_DISMISSED`;
      useTrack(
        CAPTAIN_EVENTS[eventKey],
        buildPayload(currentAction.value, current.conversationId)
      );
    }

    isContentReady.value = false;
    isEditorDismissed.value = false;

    if (!current) return;

    store.dispatch('aiGenerations/dismiss', {
      kind: current.kind,
      conversationId: current.conversationId,
    });
  }

  /**
   * Toggles the copilot editor visibility.
   */
  function toggleEditor() {
    isEditorDismissed.value = !isEditorDismissed.value;
  }

  /**
   * Marks content as ready (called after transition completes).
   */
  function setContentReady() {
    isContentReady.value = true;
  }

  /**
   * Starts an AI generation. Returns as soon as the job is queued.
   * @param {string} action - The action type
   * @param {string} [data] - Operator draft, used by prepare_answer
   */
  async function execute(action, data) {
    const kind = ACTION_KINDS[action];
    if (!kind || !conversationId.value) return;

    isContentReady.value = false;
    isEditorDismissed.value = false;

    try {
      await store.dispatch('aiGenerations/request', {
        kind,
        conversationId: conversationId.value,
        content: kind === KINDS.PREPARED_REPLY ? data : undefined,
      });
    } catch (error) {
      useAlert(
        error.response?.data?.error ||
          'Failed to generate content. Please try again.'
      );
    }
  }

  /**
   * Accepts the generated content and returns it.
   * Note: Formatting is automatically stripped by the Editor component's
   * createState function based on the channel's schema.
   * @returns {string} The content ready for the editor
   */
  function accept() {
    const current = record.value;
    if (!current) return '';

    const content = current.content;

    if (currentAction.value) {
      const eventKey = `${getEventPrefix(currentAction.value)}_APPLIED`;
      useTrack(
        CAPTAIN_EVENTS[eventKey],
        buildPayload(currentAction.value, current.conversationId)
      );
    }

    store.dispatch('aiGenerations/dismiss', {
      kind: current.kind,
      conversationId: current.conversationId,
    });

    return content;
  }

  return {
    showEditor,
    isGenerating,
    isContentReady,
    generatedContent,
    currentAction,

    isActive,
    isButtonDisabled,
    editorTransitionKey,

    reset,
    toggleEditor,
    setContentReady,
    execute,
    accept,
  };
}
