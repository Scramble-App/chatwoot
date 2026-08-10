import { actions, getters, mutations } from '../../aiGenerations';
import types from '../../../mutation-types';
import ConversationApi from 'dashboard/api/inbox/conversation';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    requestAiGeneration: vi.fn(),
    fetchAiGeneration: vi.fn(),
    dismissAiGeneration: vi.fn(),
  },
}));

describe('#aiGenerations getters', () => {
  it('returns null when nothing is stored for the conversation', () => {
    const state = { records: {} };

    expect(getters.get(state)('summary', 45)).toBeNull();
    expect(getters.active(state)(45)).toBeNull();
  });

  it('returns the record for a kind and conversation', () => {
    const record = {
      id: 1,
      kind: 'summary',
      status: 'completed',
      content: 'text',
    };
    const state = { records: { 'summary:45': record } };

    expect(getters.get(state)('summary', 45)).toEqual(record);
  });

  it('active picks the most recently updated record across kinds', () => {
    const state = {
      records: {
        'summary:45': {
          id: 1,
          kind: 'summary',
          status: 'completed',
          updated_at: 100,
        },
        'knowledge_answer:45': {
          id: 2,
          kind: 'knowledge_answer',
          status: 'completed',
          updated_at: 200,
        },
      },
    };

    expect(getters.active(state)(45).id).toEqual(2);
  });

  it('active ignores records from another conversation', () => {
    const state = {
      records: {
        'summary:99': {
          id: 1,
          kind: 'summary',
          status: 'completed',
          updated_at: 100,
        },
      },
    };

    expect(getters.active(state)(45)).toBeNull();
  });
});

describe('#aiGenerations mutations', () => {
  it('stores the record keyed by kind and conversation and tags it with the kind', () => {
    const state = { records: {} };

    mutations[types.SET_AI_GENERATION](state, {
      kind: 'knowledge_answer',
      conversationId: 45,
      record: { id: 7, status: 'pending', updated_at: 10 },
    });

    expect(state.records['knowledge_answer:45']).toEqual({
      id: 7,
      status: 'pending',
      updated_at: 10,
      kind: 'knowledge_answer',
      conversationId: 45,
    });
  });

  it('ignores a payload older than the stored one', () => {
    const state = {
      records: { 'summary:45': { id: 1, status: 'failed', updated_at: 20 } },
    };

    mutations[types.SET_AI_GENERATION](state, {
      kind: 'summary',
      conversationId: 45,
      record: { id: 1, status: 'pending', updated_at: 10 },
    });

    expect(state.records['summary:45'].status).toEqual('failed');
  });

  it('keeps a finished record over an in-progress payload from the same second', () => {
    const state = {
      records: { 'summary:45': { id: 1, status: 'failed', updated_at: 20 } },
    };

    mutations[types.SET_AI_GENERATION](state, {
      kind: 'summary',
      conversationId: 45,
      record: { id: 1, status: 'pending', updated_at: 20 },
    });

    expect(state.records['summary:45'].status).toEqual('failed');
  });

  it('applies a newer payload', () => {
    const state = {
      records: { 'summary:45': { id: 1, status: 'running', updated_at: 10 } },
    };

    mutations[types.SET_AI_GENERATION](state, {
      kind: 'summary',
      conversationId: 45,
      record: { id: 1, status: 'completed', updated_at: 20 },
    });

    expect(state.records['summary:45'].status).toEqual('completed');
  });

  it('removes a record', () => {
    const state = { records: { 'summary:45': { id: 1 } } };

    mutations[types.REMOVE_AI_GENERATION](state, {
      kind: 'summary',
      conversationId: 45,
    });

    expect(state.records['summary:45']).toBeUndefined();
  });
});

describe('#aiGenerations actions', () => {
  beforeEach(() => vi.clearAllMocks());

  it('dismiss removes the record before the delete request settles', async () => {
    let settleRequest;
    ConversationApi.dismissAiGeneration.mockReturnValue(
      new Promise(resolve => {
        settleRequest = resolve;
      })
    );
    const commit = vi.fn();

    const dismissal = actions.dismiss(
      { commit },
      { kind: 'summary', conversationId: 45 }
    );

    expect(commit).toHaveBeenCalledWith(types.REMOVE_AI_GENERATION, {
      kind: 'summary',
      conversationId: 45,
    });
    expect(ConversationApi.dismissAiGeneration).toHaveBeenCalledWith({
      conversationId: 45,
      path: 'summarize',
    });

    settleRequest({});
    await dismissal;

    expect(commit).toHaveBeenCalledTimes(1);
  });
});
