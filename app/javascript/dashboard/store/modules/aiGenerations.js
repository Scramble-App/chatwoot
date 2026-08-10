import types from '../mutation-types';
import ConversationApi from 'dashboard/api/inbox/conversation';

export const KINDS = {
  SUMMARY: 'summary',
  KNOWLEDGE_ANSWER: 'knowledge_answer',
  PREPARED_REPLY: 'prepared_reply',
};

export const KIND_LIST = Object.values(KINDS);

const KIND_PATHS = {
  [KINDS.SUMMARY]: 'summarize',
  [KINDS.KNOWLEDGE_ANSWER]: 'knowledge_answer',
  [KINDS.PREPARED_REPLY]: 'prepare_reply',
};

const recordKey = (kind, conversationId) => `${kind}:${conversationId}`;

const state = {
  records: {},
};

export const getters = {
  get: _state => (kind, conversationId) =>
    _state.records[recordKey(kind, conversationId)] || null,

  active: _state => conversationId => {
    const records = KIND_LIST.map(
      kind => _state.records[recordKey(kind, conversationId)]
    ).filter(Boolean);

    if (!records.length) return null;

    return [...records].sort((a, b) => b.updated_at - a.updated_at)[0];
  },
};

export const actions = {
  request: async ({ commit }, { kind, conversationId, content }) => {
    const { data } = await ConversationApi.requestAiGeneration({
      conversationId,
      path: KIND_PATHS[kind],
      content,
    });
    commit(types.SET_AI_GENERATION, { kind, conversationId, record: data });
  },

  fetch: async ({ commit }, { kind, conversationId }) => {
    const { status, data } = await ConversationApi.fetchAiGeneration({
      conversationId,
      path: KIND_PATHS[kind],
    });
    if (status === 204 || !data) return;

    commit(types.SET_AI_GENERATION, { kind, conversationId, record: data });
  },

  fetchAll: async ({ dispatch }, { conversationId }) => {
    await Promise.all(
      KIND_LIST.map(kind => dispatch('fetch', { kind, conversationId }))
    );
  },

  dismiss: async ({ commit }, { kind, conversationId }) => {
    commit(types.REMOVE_AI_GENERATION, { kind, conversationId });
    await ConversationApi.dismissAiGeneration({
      conversationId,
      path: KIND_PATHS[kind],
    });
  },

  updateFromEvent: ({ commit }, { kind, data }) => {
    commit(types.SET_AI_GENERATION, {
      kind,
      conversationId: data.conversation_id,
      record: data,
    });
  },
};

export const mutations = {
  [types.SET_AI_GENERATION]($state, { kind, conversationId, record }) {
    $state.records = {
      ...$state.records,
      [recordKey(kind, conversationId)]: { ...record, kind, conversationId },
    };
  },

  [types.REMOVE_AI_GENERATION]($state, { kind, conversationId }) {
    const { [recordKey(kind, conversationId)]: removed, ...rest } =
      $state.records;
    $state.records = rest;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
