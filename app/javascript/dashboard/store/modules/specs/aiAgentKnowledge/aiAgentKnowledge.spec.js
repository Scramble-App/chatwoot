import {
  actions,
  getters,
  mutations,
  initialState,
  types,
} from '../../aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    getKnowledgeBases: vi.fn(),
    getEntries: vi.fn(),
    showEntry: vi.fn(),
    createEntry: vi.fn(),
    updateEntry: vi.fn(),
    deleteEntry: vi.fn(),
    importEntries: vi.fn(),
    exportEntries: vi.fn(),
  },
}));

vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));

const apiMeta = {
  count: 2,
  current_page: 1,
  per_page: 50,
  categories: ['Pricing', 'Eligibility'],
  status_counts: { draft: 1, published: 1, needs_answer: 0 },
};

const entry = {
  id: 12,
  key: 'KB-012',
  question: 'How long does a review take?',
  status: 'published',
};

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

describe('#aiAgentKnowledge getters', () => {
  it('returns knowledge bases, entries, meta and ui flags', () => {
    const state = {
      ...initialState(),
      knowledgeBases: [{ id: 1, name: 'Assistant' }],
      records: [entry],
    };

    expect(getters.getKnowledgeBases(state)).toEqual([
      { id: 1, name: 'Assistant' },
    ]);
    expect(getters.getEntries(state)).toEqual([entry]);
    expect(getters.getMeta(state)).toEqual(state.meta);
    expect(getters.getUIFlags(state).isFetching).toBe(false);
  });
});

describe('#aiAgentKnowledge mutations', () => {
  it('merges ui flags', () => {
    const state = initialState();
    mutations[types.SET_UI_FLAG](state, { isExporting: true });

    expect(state.uiFlags).toEqual({ isFetching: false, isExporting: true });
  });

  it('stores the knowledge bases and entries', () => {
    const state = initialState();
    mutations[types.SET_KNOWLEDGE_BASES](state, [{ id: 1 }]);
    mutations[types.SET_ENTRIES](state, [entry]);

    expect(state.knowledgeBases).toEqual([{ id: 1 }]);
    expect(state.records).toEqual([entry]);
  });

  it('maps the index meta', () => {
    const state = initialState();
    mutations[types.SET_META](state, apiMeta);

    expect(state.meta).toEqual({
      count: 2,
      currentPage: 1,
      perPage: 50,
      categories: ['Pricing', 'Eligibility'],
      statusCounts: { draft: 1, published: 1, needs_answer: 0 },
    });
  });

  it('falls back to empty categories and zero counts', () => {
    const state = initialState();
    mutations[types.SET_META](state, {
      count: 0,
      current_page: 1,
      per_page: 50,
    });

    expect(state.meta.categories).toEqual([]);
    expect(state.meta.statusCounts).toEqual({
      draft: 0,
      published: 0,
      needs_answer: 0,
    });
  });

  it('resets the entries and meta', () => {
    const state = { ...initialState(), records: [entry] };
    mutations[types.SET_META](state, apiMeta);
    mutations[types.RESET_ENTRIES](state);

    expect(state.records).toEqual([]);
    expect(state.meta).toEqual(initialState().meta);
  });
});

describe('#aiAgentKnowledge actions', () => {
  const commit = vi.fn();

  describe('#fetchKnowledgeBases', () => {
    it('stores the manageable knowledge bases', async () => {
      const knowledgeBases = [
        { id: 1, name: 'Assistant', thumbnail: '', needs_answer_count: 3 },
      ];
      AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({
        data: knowledgeBases,
      });

      await actions.fetchKnowledgeBases({ commit });

      expect(commit.mock.calls).toEqual([
        [types.SET_KNOWLEDGE_BASES, knowledgeBases],
      ]);
    });

    it('swallows errors and keeps the list', async () => {
      AiAgentKnowledgeAPI.getKnowledgeBases.mockRejectedValue(
        new Error('Network Error')
      );

      await expect(
        actions.fetchKnowledgeBases({ commit })
      ).resolves.toBeUndefined();

      expect(commit).not.toHaveBeenCalled();
    });
  });

  describe('#fetchEntries', () => {
    it('fetches the entries of the bot with the filters', async () => {
      AiAgentKnowledgeAPI.getEntries.mockResolvedValue({
        data: { payload: [entry], meta: apiMeta },
      });

      await actions.fetchEntries(
        { commit },
        { botId: 7, status: 'needs_answer', sort: 'asked_count', page: 2 }
      );

      expect(AiAgentKnowledgeAPI.getEntries).toHaveBeenCalledWith(7, {
        status: 'needs_answer',
        sort: 'asked_count',
        page: 2,
      });
      expect(commit.mock.calls).toEqual([
        [types.SET_UI_FLAG, { isFetching: true }],
        [types.SET_ENTRIES, [entry]],
        [types.SET_META, apiMeta],
        [types.SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('rethrows the API error so the page can tell no access apart', async () => {
      const error = { response: { status: 403 } };
      AiAgentKnowledgeAPI.getEntries.mockRejectedValue(error);

      await expect(actions.fetchEntries({ commit }, { botId: 7 })).rejects.toBe(
        error
      );
      expect(commit).toHaveBeenLastCalledWith(types.SET_UI_FLAG, {
        isFetching: false,
      });
    });

    it('drops the response of a superseded request', async () => {
      const first = deferred();
      const second = deferred();
      AiAgentKnowledgeAPI.getEntries
        .mockReturnValueOnce(first.promise)
        .mockReturnValueOnce(second.promise);

      const firstRequest = actions.fetchEntries({ commit }, { botId: 7 });
      const secondRequest = actions.fetchEntries(
        { commit },
        { botId: 7, q: 'fees' }
      );

      second.resolve({ data: { payload: [entry], meta: apiMeta } });
      await secondRequest;
      first.resolve({ data: { payload: [], meta: apiMeta } });
      await firstRequest;

      const entryCommits = commit.mock.calls.filter(
        ([type]) => type === types.SET_ENTRIES
      );
      expect(entryCommits).toEqual([[types.SET_ENTRIES, [entry]]]);
    });

    it('ignores the error of a superseded request', async () => {
      const first = deferred();
      AiAgentKnowledgeAPI.getEntries
        .mockReturnValueOnce(first.promise)
        .mockResolvedValueOnce({ data: { payload: [entry], meta: apiMeta } });

      const firstRequest = actions.fetchEntries({ commit }, { botId: 7 });
      await actions.fetchEntries({ commit }, { botId: 7, q: 'fees' });
      first.reject({ response: { status: 500 } });

      await expect(firstRequest).resolves.toBeNull();
    });
  });

  it('#showEntry returns the entry with its customer wordings', async () => {
    const data = { ...entry, questions: [{ id: 1, content: 'Fees?' }] };
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({ data });

    await expect(
      actions.showEntry({ commit }, { botId: 7, id: 12 })
    ).resolves.toEqual(data);
    expect(AiAgentKnowledgeAPI.showEntry).toHaveBeenCalledWith(7, 12);
  });

  it('#createEntry posts the entry to the bot', async () => {
    AiAgentKnowledgeAPI.createEntry.mockResolvedValue({ data: entry });

    await expect(
      actions.createEntry(
        { commit },
        { botId: 7, question: entry.question, status: 'draft' }
      )
    ).resolves.toEqual(entry);

    expect(AiAgentKnowledgeAPI.createEntry).toHaveBeenCalledWith(7, {
      question: entry.question,
      status: 'draft',
    });
    expect(commit).not.toHaveBeenCalled();
  });

  it('#updateEntry patches the entry and rethrows validation errors', async () => {
    const error = {
      response: {
        status: 422,
        data: { message: 'Key has already been taken' },
      },
    };
    AiAgentKnowledgeAPI.updateEntry.mockRejectedValue(error);

    await expect(
      actions.updateEntry({ commit }, { botId: 7, id: 12, key: 'KB-001' })
    ).rejects.toBe(error);

    expect(AiAgentKnowledgeAPI.updateEntry).toHaveBeenCalledWith(7, 12, {
      key: 'KB-001',
    });
  });

  it('#deleteEntry deletes the entry', async () => {
    AiAgentKnowledgeAPI.deleteEntry.mockResolvedValue({});

    await actions.deleteEntry({ commit }, { botId: 7, id: 12 });

    expect(AiAgentKnowledgeAPI.deleteEntry).toHaveBeenCalledWith(7, 12);
    expect(commit).not.toHaveBeenCalled();
  });

  it('#importEntries sends the file and returns the result', async () => {
    const file = new File(['ID'], 'kb.csv');
    const result = { created: 2, updated: 1, errors: [] };
    AiAgentKnowledgeAPI.importEntries.mockResolvedValue({ data: result });

    await expect(
      actions.importEntries({ commit }, { botId: 7, file, dryRun: true })
    ).resolves.toEqual(result);

    expect(AiAgentKnowledgeAPI.importEntries).toHaveBeenCalledWith(7, {
      file,
      dryRun: true,
    });
    expect(commit).not.toHaveBeenCalled();
  });

  it('#exportEntries downloads the CSV named after the bot', async () => {
    const blob = new Blob(['﻿ID'], { type: 'text/csv' });
    AiAgentKnowledgeAPI.exportEntries.mockResolvedValue({ data: blob });

    await actions.exportEntries({ commit }, { botId: 7 });

    expect(AiAgentKnowledgeAPI.exportEntries).toHaveBeenCalledWith(7);
    expect(downloadCsvFile).toHaveBeenCalledWith('knowledge-base-7.csv', blob);
    expect(commit.mock.calls).toEqual([
      [types.SET_UI_FLAG, { isExporting: true }],
      [types.SET_UI_FLAG, { isExporting: false }],
    ]);
  });

  it('#resetEntries clears the list', () => {
    actions.resetEntries({ commit });
    expect(commit).toHaveBeenCalledWith(types.RESET_ENTRIES);
  });
});
