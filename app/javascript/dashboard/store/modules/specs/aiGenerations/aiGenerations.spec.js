import { getters, mutations } from '../../aiGenerations';
import types from '../../../mutation-types';

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

  it('removes a record', () => {
    const state = { records: { 'summary:45': { id: 1 } } };

    mutations[types.REMOVE_AI_GENERATION](state, {
      kind: 'summary',
      conversationId: 45,
    });

    expect(state.records['summary:45']).toBeUndefined();
  });
});
