import aiAgentKnowledgeAPI, { buildEntriesParams } from '../aiAgentKnowledge';
import ApiClient from '../ApiClient';

describe('#AiAgentKnowledgeAPI', () => {
  it('creates correct instance', () => {
    expect(aiAgentKnowledgeAPI).toBeInstanceOf(ApiClient);
    expect(aiAgentKnowledgeAPI).toHaveProperty('getKnowledgeBases');
    expect(aiAgentKnowledgeAPI).toHaveProperty('getEntries');
    expect(aiAgentKnowledgeAPI).toHaveProperty('showEntry');
    expect(aiAgentKnowledgeAPI).toHaveProperty('createEntry');
    expect(aiAgentKnowledgeAPI).toHaveProperty('updateEntry');
    expect(aiAgentKnowledgeAPI).toHaveProperty('deleteEntry');
    expect(aiAgentKnowledgeAPI).toHaveProperty('importEntries');
    expect(aiAgentKnowledgeAPI).toHaveProperty('exportEntries');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getKnowledgeBases', () => {
      aiAgentKnowledgeAPI.getKnowledgeBases();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/knowledge_bases'
      );
    });

    it('#getEntries sends the filters as query params', () => {
      aiAgentKnowledgeAPI.getEntries(7, {
        q: 'repayment',
        category: 'Pricing',
        status: 'needs_answer',
        sort: 'asked_count',
        page: 2,
      });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries',
        {
          params: {
            q: 'repayment',
            category: 'Pricing',
            status: 'needs_answer',
            sort: 'asked_count',
            page: 2,
          },
        }
      );
    });

    it('#getEntries leaves out blank filters', () => {
      aiAgentKnowledgeAPI.getEntries(7, { q: '', status: '', page: 1 });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries',
        { params: { page: 1 } }
      );
    });

    it('#showEntry', () => {
      aiAgentKnowledgeAPI.showEntry(7, 12);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries/12'
      );
    });

    it('#createEntry', () => {
      const entry = { question: 'How long does a review take?' };
      aiAgentKnowledgeAPI.createEntry(7, entry);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries',
        entry
      );
    });

    it('#updateEntry', () => {
      const entry = { status: 'published' };
      aiAgentKnowledgeAPI.updateEntry(7, 12, entry);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries/12',
        entry
      );
    });

    it('#deleteEntry', () => {
      aiAgentKnowledgeAPI.deleteEntry(7, 12);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries/12'
      );
    });

    it('#importEntries posts the file and dry_run as multipart', () => {
      const file = new File(['ID,Вопрос'], 'kb.csv', { type: 'text/csv' });
      aiAgentKnowledgeAPI.importEntries(7, { file, dryRun: true });

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries/import',
        expect.any(FormData),
        { headers: { 'Content-Type': 'multipart/form-data' } }
      );
      const formData = axiosMock.post.mock.calls[0][1];
      expect(formData.get('file')).toBe(file);
      expect(formData.get('dry_run')).toBe('true');
    });

    it('#importEntries sends dry_run false to apply the import', () => {
      const file = new File(['ID,Вопрос'], 'kb.csv', { type: 'text/csv' });
      aiAgentKnowledgeAPI.importEntries(7, { file, dryRun: false });

      const formData = axiosMock.post.mock.calls[0][1];
      expect(formData.get('dry_run')).toBe('false');
    });

    it('#exportEntries downloads the CSV as a blob', () => {
      aiAgentKnowledgeAPI.exportEntries(7);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/7/knowledge_entries/export',
        { responseType: 'blob' }
      );
    });
  });
});

describe('#buildEntriesParams', () => {
  it('keeps only known, non-blank filters', () => {
    expect(
      buildEntriesParams({
        q: 'fees',
        category: '',
        status: undefined,
        sort: 'key',
        page: 3,
        unknown: 'x',
      })
    ).toEqual({ q: 'fees', sort: 'key', page: 3 });
  });

  it('returns no params without filters', () => {
    expect(buildEntriesParams()).toEqual({});
  });
});
