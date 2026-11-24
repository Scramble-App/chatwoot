import AgentBotsAPI from '../agentBots';
import ApiClient from '../ApiClient';

describe('#AgentBotsAPI', () => {
  it('creates correct instance', () => {
    expect(AgentBotsAPI).toBeInstanceOf(ApiClient);
    expect(AgentBotsAPI).toHaveProperty('get');
    expect(AgentBotsAPI).toHaveProperty('show');
    expect(AgentBotsAPI).toHaveProperty('create');
    expect(AgentBotsAPI).toHaveProperty('update');
    expect(AgentBotsAPI).toHaveProperty('delete');
    expect(AgentBotsAPI).toHaveProperty('resetAccessToken');
    expect(AgentBotsAPI).toHaveProperty('getAiAgentDefaults');
    expect(AgentBotsAPI).toHaveProperty('getPages');
    expect(AgentBotsAPI).toHaveProperty('createPage');
    expect(AgentBotsAPI).toHaveProperty('deletePage');
    expect(AgentBotsAPI).toHaveProperty('refreshPage');
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

    it('#getAiAgentDefaults', () => {
      AgentBotsAPI.getAiAgentDefaults();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/agent_bots/ai_agent_defaults'
      );
    });

    it('#getPages', () => {
      AgentBotsAPI.getPages(3);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/agent_bots/3/pages');
    });

    it('#createPage', () => {
      AgentBotsAPI.createPage(3, 'https://example.com/pricing');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/agent_bots/3/pages',
        { url: 'https://example.com/pricing' }
      );
    });

    it('#deletePage', () => {
      AgentBotsAPI.deletePage(3, 7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/agent_bots/3/pages/7'
      );
    });

    it('#refreshPage', () => {
      AgentBotsAPI.refreshPage(3, 7);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/agent_bots/3/pages/7/refresh'
      );
    });
  });
});
