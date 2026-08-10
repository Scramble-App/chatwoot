import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import { useAlert, useTrack } from 'dashboard/composables';
import ConversationApi from 'dashboard/api/inbox/conversation';
import aiGenerations from 'dashboard/store/modules/aiGenerations';
import types from 'dashboard/store/mutation-types';
import { useCopilotReply } from '../useCopilotReply';

vi.mock('dashboard/composables/store.js');
vi.mock('dashboard/composables');
vi.mock('vue-i18n');
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    requestAiGeneration: vi.fn(),
    fetchAiGeneration: vi.fn(),
    dismissAiGeneration: vi.fn(),
  },
}));

const CONVERSATION_ID = 45;

const setRecord = (store, kind, attributes) =>
  store.commit(`aiGenerations/${types.SET_AI_GENERATION}`, {
    kind,
    conversationId: CONVERSATION_ID,
    record: { id: 1, updated_at: 10, ...attributes },
  });

describe('useCopilotReply', () => {
  let store;
  let copilot;
  let wrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    // The module exports a shared state object, so each store gets a fresh one.
    store = createStore({
      modules: { aiGenerations: { ...aiGenerations, state: { records: {} } } },
    });
    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(getter =>
      getter === 'getSelectedChat' ? { value: { id: CONVERSATION_ID } } : {}
    );
    useI18n.mockReturnValue({ t: key => key });
    ConversationApi.fetchAiGeneration.mockResolvedValue({ status: 204 });
    ConversationApi.dismissAiGeneration.mockResolvedValue({});

    wrapper = mount({
      setup() {
        copilot = useCopilotReply();
        return () => null;
      },
    });
  });

  afterEach(() => wrapper.unmount());

  describe('analytics', () => {
    it('tracks the used event once a summary arrives completed', async () => {
      setRecord(store, 'summary', { status: 'completed', content: 'summary' });
      await nextTick();

      expect(useTrack).toHaveBeenCalledWith('Captain: Summarize used', {
        conversationId: CONVERSATION_ID,
      });
    });

    it('tracks the used event for a knowledge answer as a reply suggestion', async () => {
      setRecord(store, 'knowledge_answer', {
        status: 'completed',
        content: 'answer',
      });
      await nextTick();

      expect(useTrack).toHaveBeenCalledWith('Captain: Reply suggestion used', {
        conversationId: CONVERSATION_ID,
      });
    });

    it('does not track the used event twice for the same generation', async () => {
      setRecord(store, 'summary', { status: 'completed', content: 'summary' });
      await nextTick();
      setRecord(store, 'summary', {
        status: 'completed',
        content: 'summary',
        updated_at: 20,
      });
      await nextTick();

      expect(useTrack).toHaveBeenCalledTimes(1);
    });

    it('does not track the used event while the generation is still running', async () => {
      setRecord(store, 'summary', { status: 'running' });
      await nextTick();

      expect(useTrack).not.toHaveBeenCalled();
    });

    it('tracks the failure event when a generation arrives failed', async () => {
      setRecord(store, 'summary', {
        status: 'failed',
        error_message: 'Onyx MCP is not configured',
      });
      await nextTick();

      expect(useTrack).toHaveBeenCalledWith('Captain: Generation failed', {
        conversationId: CONVERSATION_ID,
        stage: 'initial',
        reason: 'exception',
      });
    });
  });

  describe('failure handling', () => {
    it('alerts and dismisses every failed generation, not only the active one', async () => {
      setRecord(store, 'summary', {
        status: 'failed',
        error_message: 'summary failed',
      });
      setRecord(store, 'knowledge_answer', {
        status: 'failed',
        error_message: 'knowledge answer failed',
        updated_at: 20,
      });
      await nextTick();

      expect(useAlert).toHaveBeenCalledWith('summary failed');
      expect(useAlert).toHaveBeenCalledWith('knowledge answer failed');
      expect(ConversationApi.dismissAiGeneration).toHaveBeenCalledWith({
        conversationId: CONVERSATION_ID,
        path: 'summarize',
      });
      expect(ConversationApi.dismissAiGeneration).toHaveBeenCalledWith({
        conversationId: CONVERSATION_ID,
        path: 'knowledge_answer',
      });
      expect(store.getters['aiGenerations/active'](CONVERSATION_ID)).toBeNull();
    });

    it('does not resurface an older completed generation when a newer one fails', async () => {
      setRecord(store, 'summary', {
        status: 'completed',
        content: 'summary',
      });
      setRecord(store, 'knowledge_answer', {
        status: 'failed',
        error_message: 'knowledge answer failed',
        updated_at: 20,
      });
      await nextTick();

      expect(copilot.generatedContent.value).toEqual('summary');
      expect(useAlert).toHaveBeenCalledWith('knowledge answer failed');
    });
  });

  describe('execute', () => {
    it('alerts with a translated fallback and tracks the failure when queuing fails', async () => {
      ConversationApi.requestAiGeneration.mockRejectedValue(new Error('boom'));

      await copilot.execute('summarize');

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.REPLYBOX.COPILOT_GENERATION_ERROR'
      );
      expect(useTrack).toHaveBeenCalledWith('Captain: Generation failed', {
        conversationId: CONVERSATION_ID,
        stage: 'initial',
        reason: 'exception',
      });
    });
  });
});
