import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import Sidebar from '../Sidebar.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    getKnowledgeBases: vi.fn(),
  },
}));

// Declares the props so the menu items can be read without rendering the groups
const SidebarGroupStub = {
  name: 'SidebarGroup',
  props: ['name', 'label', 'icon', 'to', 'activeOn', 'children', 'getterKeys'],
  template: '<li />',
};

const mountSidebar = async () => {
  const store = createStore({
    modules: { aiAgentKnowledge },
    getters: {
      getCurrentAccountId: () => 1,
      getUISettings: () => ({}),
      'accounts/getAccount': () => () => ({}),
      'accounts/isRTL': () => false,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'globalConfig/isOnChatwootCloud': () => false,
      'globalConfig/isACustomBrandedInstance': () => false,
      'inboxes/getInboxes': () => [],
      'labels/getLabelsOnSidebar': () => [],
      'teams/getMyTeams': () => [],
      'customViews/getContactCustomViews': () => [],
      'customViews/getConversationCustomViews': () => [],
    },
  });
  // Only the knowledge base list is under test, the other loads are ignored
  const { dispatch } = store;
  store.dispatch = vi.fn((type, payload) =>
    type.startsWith('aiAgentKnowledge/')
      ? dispatch(type, payload)
      : Promise.resolve()
  );

  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/:page',
        name: 'dashboard_page',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/app/accounts/1/dashboard');
  await router.isReady();

  const wrapper = shallowMount(Sidebar, {
    global: {
      plugins: [store, router],
      stubs: { SidebarGroup: SidebarGroupStub },
    },
  });
  await flushPromises();
  return { wrapper, store };
};

const menuNames = wrapper =>
  wrapper
    .findAllComponents({ name: 'SidebarGroup' })
    .map(group => group.props('name'));

describe('Sidebar AI agent entry', () => {
  it('loads the manageable knowledge bases once and hides the entry without any', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({ data: [] });
    const { wrapper, store } = await mountSidebar();

    expect(store.dispatch).toHaveBeenCalledWith(
      'aiAgentKnowledge/fetchKnowledgeBases'
    );
    expect(AiAgentKnowledgeAPI.getKnowledgeBases).toHaveBeenCalledTimes(1);
    expect(menuNames(wrapper)).not.toContain('AI Agent');
  });

  it('hides the entry when the list cannot be loaded', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockRejectedValue({
      response: { status: 500 },
    });
    const { wrapper } = await mountSidebar();

    expect(menuNames(wrapper)).not.toContain('AI Agent');
  });

  it('links the entry to the first manageable bot after Conversations', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({
      data: [
        { id: 7, name: 'Founders Assistant', needs_answer_count: 2 },
        { id: 9, name: 'Second Assistant', needs_answer_count: 0 },
      ],
    });
    const { wrapper } = await mountSidebar();

    const names = menuNames(wrapper);
    expect(names.indexOf('AI Agent')).toBe(names.indexOf('Conversation') + 1);

    const entry = wrapper
      .findAllComponents({ name: 'SidebarGroup' })
      .find(group => group.props('name') === 'AI Agent');
    expect(entry.props()).toMatchObject({
      label: 'AI agent',
      icon: 'i-lucide-bot',
      to: {
        name: 'ai_agent_knowledge',
        params: { accountId: 1, botId: 7 },
      },
      activeOn: ['ai_agent_index', 'ai_agent_knowledge'],
    });
  });
});
