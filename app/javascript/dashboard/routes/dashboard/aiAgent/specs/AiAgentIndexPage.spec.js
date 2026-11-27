import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import AiAgentIndexPage from '../pages/AiAgentIndexPage.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    getKnowledgeBases: vi.fn(),
  },
}));

const mountPage = async () => {
  const store = createStore({ modules: { aiAgentKnowledge } });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/ai-agent',
        name: 'ai_agent_index',
        component: { template: '<div />' },
      },
      {
        path: '/app/accounts/:accountId/ai-agent/:botId/knowledge',
        name: 'ai_agent_knowledge',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/app/accounts/1/ai-agent');
  await router.isReady();

  const wrapper = mount(AiAgentIndexPage, {
    global: { plugins: [store, router] },
  });
  await flushPromises();
  return { wrapper, router };
};

describe('AiAgentIndexPage', () => {
  it('opens the knowledge base of the first manageable bot', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({
      data: [
        { id: 9, name: 'Founders Assistant', needs_answer_count: 0 },
        { id: 4, name: 'Second Assistant', needs_answer_count: 2 },
      ],
    });
    const { router } = await mountPage();

    expect(router.currentRoute.value.fullPath).toBe(
      '/app/accounts/1/ai-agent/9/knowledge'
    );
  });

  it('explains who manages knowledge bases when there is none to manage', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({ data: [] });
    const { wrapper, router } = await mountPage();

    expect(router.currentRoute.value.name).toBe('ai_agent_index');
    expect(wrapper.text()).toContain('No knowledge bases to manage');
  });

  it('shows the same state when the list cannot be loaded', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockRejectedValue({
      response: { status: 500 },
    });
    const { wrapper, router } = await mountPage();

    expect(router.currentRoute.value.name).toBe('ai_agent_index');
    expect(wrapper.text()).toContain('No knowledge bases to manage');
  });
});
