import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

export const types = {
  SET_UI_FLAG: 'SET_AI_AGENT_KNOWLEDGE_UI_FLAG',
  SET_KNOWLEDGE_BASES: 'SET_AI_AGENT_KNOWLEDGE_BASES',
  SET_ENTRIES: 'SET_AI_AGENT_KNOWLEDGE_ENTRIES',
  SET_META: 'SET_AI_AGENT_KNOWLEDGE_META',
  RESET_ENTRIES: 'RESET_AI_AGENT_KNOWLEDGE_ENTRIES',
};

const initialMeta = () => ({
  count: 0,
  currentPage: 1,
  perPage: 50,
  categories: [],
  statusCounts: { draft: 0, published: 0, needs_answer: 0 },
});

export const initialState = () => ({
  knowledgeBases: [],
  records: [],
  meta: initialMeta(),
  uiFlags: {
    isFetchingKnowledgeBases: false,
    hasFetchedKnowledgeBases: false,
    isFetching: false,
    isSaving: false,
    isDeleting: false,
    isImporting: false,
    isExporting: false,
  },
});

// Only the latest entries request may update the list, so a slow response to an
// earlier search or filter never replaces newer results
let latestEntriesRequest = 0;

export const getters = {
  getKnowledgeBases: $state => $state.knowledgeBases,
  getEntries: $state => $state.records,
  getMeta: $state => $state.meta,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  async fetchKnowledgeBases({ commit }) {
    commit(types.SET_UI_FLAG, { isFetchingKnowledgeBases: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.getKnowledgeBases();
      commit(types.SET_KNOWLEDGE_BASES, data);
    } catch (error) {
      // Without the list the sidebar entry and the bot switcher stay hidden
    } finally {
      commit(types.SET_UI_FLAG, {
        isFetchingKnowledgeBases: false,
        hasFetchedKnowledgeBases: true,
      });
    }
  },

  async fetchEntries({ commit }, { botId, ...filters }) {
    latestEntriesRequest += 1;
    const requestId = latestEntriesRequest;
    const isLatest = () => requestId === latestEntriesRequest;

    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.getEntries(botId, filters);
      if (!isLatest()) return null;

      commit(types.SET_ENTRIES, data.payload);
      commit(types.SET_META, data.meta);
      return data;
    } catch (error) {
      if (isLatest()) throw error;
      return null;
    } finally {
      if (isLatest()) commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  async showEntry(_, { botId, id }) {
    const { data } = await AiAgentKnowledgeAPI.showEntry(botId, id);
    return data;
  },

  async createEntry({ commit }, { botId, ...entry }) {
    commit(types.SET_UI_FLAG, { isSaving: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.createEntry(botId, entry);
      return data;
    } finally {
      commit(types.SET_UI_FLAG, { isSaving: false });
    }
  },

  async updateEntry({ commit }, { botId, id, ...entry }) {
    commit(types.SET_UI_FLAG, { isSaving: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.updateEntry(botId, id, entry);
      return data;
    } finally {
      commit(types.SET_UI_FLAG, { isSaving: false });
    }
  },

  async deleteEntry({ commit }, { botId, id }) {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await AiAgentKnowledgeAPI.deleteEntry(botId, id);
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
    }
  },

  async importEntries({ commit }, { botId, file, dryRun }) {
    commit(types.SET_UI_FLAG, { isImporting: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.importEntries(botId, {
        file,
        dryRun,
      });
      return data;
    } finally {
      commit(types.SET_UI_FLAG, { isImporting: false });
    }
  },

  async exportEntries({ commit }, { botId }) {
    commit(types.SET_UI_FLAG, { isExporting: true });
    try {
      const { data } = await AiAgentKnowledgeAPI.exportEntries(botId);
      downloadCsvFile(`knowledge-base-${botId}.csv`, data);
    } finally {
      commit(types.SET_UI_FLAG, { isExporting: false });
    }
  },

  resetEntries({ commit }) {
    commit(types.RESET_ENTRIES);
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  [types.SET_KNOWLEDGE_BASES]($state, knowledgeBases) {
    $state.knowledgeBases = knowledgeBases;
  },
  [types.SET_ENTRIES]($state, records) {
    $state.records = records;
  },
  [types.SET_META]($state, meta) {
    const defaults = initialMeta();
    $state.meta = {
      count: meta.count,
      currentPage: meta.current_page,
      perPage: meta.per_page,
      categories: meta.categories || defaults.categories,
      statusCounts: { ...defaults.statusCounts, ...meta.status_counts },
    };
  },
  [types.RESET_ENTRIES]($state) {
    $state.records = [];
    $state.meta = initialMeta();
  },
};

export default {
  namespaced: true,
  state: initialState,
  getters,
  actions,
  mutations,
};
