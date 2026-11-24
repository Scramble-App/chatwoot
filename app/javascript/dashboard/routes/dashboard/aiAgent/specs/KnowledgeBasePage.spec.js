import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { useAlert } from 'dashboard/composables';
import KnowledgeBasePage from '../pages/KnowledgeBasePage.vue';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    getKnowledgeBases: vi.fn(),
    getEntries: vi.fn(),
    exportEntries: vi.fn(),
  },
}));

vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const knowledgeBases = [
  { id: 7, name: 'Founders Assistant', thumbnail: '', needs_answer_count: 1 },
  { id: 9, name: 'Second Assistant', thumbnail: '', needs_answer_count: 0 },
];

const entries = [
  {
    id: 1,
    key: 'KB-001',
    category: 'Pricing',
    question: 'How is the monthly repayment calculated?',
    status: 'published',
    asked_count: 0,
    last_asked_at: null,
  },
  {
    id: 2,
    key: 'KB-002',
    category: '',
    question: 'Do you fund brands outside the EU?',
    status: 'needs_answer',
    asked_count: 3,
    last_asked_at: null,
  },
];

const entriesResponse = (payload = entries, meta = {}) => ({
  data: {
    payload,
    meta: {
      count: payload.length,
      current_page: 1,
      per_page: 50,
      categories: ['Pricing', 'Eligibility'],
      status_counts: { draft: 0, published: 1, needs_answer: 1 },
      ...meta,
    },
  },
});

const openDialog = vi.fn();

const dialogStub = name => ({
  name,
  emits: ['saved', 'deleted', 'imported'],
  methods: {
    open(...args) {
      openDialog(name, ...args);
    },
  },
  template: '<div />',
});

const mountPage = async ({ query = {}, botId = 7 } = {}) => {
  const store = createStore({ modules: { aiAgentKnowledge } });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/ai-agent/:botId/knowledge',
        name: 'ai_agent_knowledge',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push({
    name: 'ai_agent_knowledge',
    params: { accountId: 1, botId },
    query,
  });
  await router.isReady();

  const wrapper = mount(KnowledgeBasePage, {
    global: {
      plugins: [store, router],
      stubs: {
        KnowledgeEntryDialog: dialogStub('KnowledgeEntryDialog'),
        DeleteEntryDialog: dialogStub('DeleteEntryDialog'),
        KnowledgeImportDialog: dialogStub('KnowledgeImportDialog'),
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
};

const lastEntriesCall = () => AiAgentKnowledgeAPI.getEntries.mock.calls.at(-1);

const findButton = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

describe('KnowledgeBasePage', () => {
  beforeEach(() => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({
      data: knowledgeBases,
    });
    AiAgentKnowledgeAPI.getEntries.mockResolvedValue(entriesResponse());
  });

  it('lists the entries of the bot with key, question, category and status', async () => {
    const { wrapper } = await mountPage();

    expect(AiAgentKnowledgeAPI.getKnowledgeBases).toHaveBeenCalled();
    expect(AiAgentKnowledgeAPI.getEntries).toHaveBeenCalledTimes(1);
    const [botId, filters] = lastEntriesCall();
    expect(botId).toBe(7);
    expect(filters).toMatchObject({ q: '', category: '', status: '', page: 1 });
    expect(filters.sort).toBeUndefined();

    const text = wrapper.text();
    expect(text).toContain('Founders Assistant');
    expect(text).toContain('KB-001');
    expect(text).toContain('How is the monthly repayment calculated?');
    expect(text).toContain('Pricing');
    expect(text).toContain('Published');
    expect(text).toContain('Needs answer');
    expect(text).toContain('Asked 3 times');
  });

  it('shows the status counts on the filters', async () => {
    const { wrapper } = await mountPage();

    expect(findButton(wrapper, 'All').text()).toContain('2');
    expect(findButton(wrapper, 'Published').text()).toContain('1');
    expect(findButton(wrapper, 'Draft').text()).toContain('0');
  });

  it('filters by needs answer and sorts that list by asked count', async () => {
    const { wrapper, router } = await mountPage();

    await findButton(wrapper, 'Needs answer').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.query.status).toBe('needs_answer');
    expect(lastEntriesCall()[1]).toMatchObject({
      status: 'needs_answer',
      sort: 'asked_count',
      page: 1,
    });
  });

  it('sends the search as q after the user stops typing', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    const { wrapper, router } = await mountPage();

    const input = wrapper.find('input[type="search"]');
    await input.setValue('repay');
    await input.setValue('repayment ');
    vi.advanceTimersByTime(399);
    await flushPromises();
    expect(AiAgentKnowledgeAPI.getEntries).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(1);
    await flushPromises();
    vi.useRealTimers();

    expect(router.currentRoute.value.query.q).toBe('repayment');
    expect(AiAgentKnowledgeAPI.getEntries).toHaveBeenCalledTimes(2);
    expect(lastEntriesCall()[1]).toMatchObject({ q: 'repayment', page: 1 });
    expect(input.element.value).toBe('repayment ');
  });

  it('takes the filters and page from the URL', async () => {
    await mountPage({ query: { category: 'Pricing', q: 'fees', page: '2' } });

    expect(lastEntriesCall()[1]).toMatchObject({
      category: 'Pricing',
      q: 'fees',
      page: 2,
    });
  });

  it('opens another page from the pagination footer', async () => {
    AiAgentKnowledgeAPI.getEntries.mockResolvedValue(
      entriesResponse(entries, { count: 120 })
    );
    const { wrapper, router } = await mountPage();

    const nextPage = wrapper
      .findAll('button')
      .find(button => button.find('.i-lucide-chevron-right').exists());
    await nextPage.trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.query.page).toBe('2');
    expect(lastEntriesCall()[1]).toMatchObject({ page: 2 });
  });

  it('hides the pagination footer when everything fits on one page', async () => {
    const { wrapper } = await mountPage();

    expect(wrapper.find('footer').exists()).toBe(false);
  });

  it('goes back to the last page when the page is past the end', async () => {
    AiAgentKnowledgeAPI.getEntries
      .mockResolvedValueOnce(
        entriesResponse([], { count: 60, current_page: 3 })
      )
      .mockResolvedValue(entriesResponse(entries, { count: 60 }));
    const { router } = await mountPage({ query: { page: '3' } });

    expect(router.currentRoute.value.query.page).toBe('2');
    expect(lastEntriesCall()[1]).toMatchObject({ page: 2 });
  });

  it.each([401, 403, 404])(
    'shows the no access state when the API answers %i',
    async status => {
      AiAgentKnowledgeAPI.getEntries.mockRejectedValue({
        response: { status },
      });
      const { wrapper } = await mountPage();

      expect(wrapper.text()).toContain("You can't open this knowledge base");
      expect(findButton(wrapper, 'New entry')).toBeUndefined();
      expect(findButton(wrapper, 'Import')).toBeUndefined();
      expect(useAlert).not.toHaveBeenCalled();
    }
  );

  it('shows an error alert for other failures', async () => {
    AiAgentKnowledgeAPI.getEntries.mockRejectedValue({
      response: { status: 500 },
    });
    const { wrapper } = await mountPage();

    expect(useAlert).toHaveBeenCalledWith(
      'Could not load the knowledge base. Please try again.'
    );
    expect(wrapper.text()).not.toContain("You can't open this knowledge base");
  });

  it('tells an empty knowledge base apart from a search without results', async () => {
    AiAgentKnowledgeAPI.getEntries.mockResolvedValue(entriesResponse([]));

    const { wrapper: empty } = await mountPage();
    expect(empty.text()).toContain('No entries yet');

    const { wrapper: filtered } = await mountPage({ query: { q: 'nothing' } });
    expect(filtered.text()).toContain('No matching entries');
  });

  it('switches to another bot from the header', async () => {
    const { wrapper, router } = await mountPage();

    await wrapper.find('button[aria-label="Switch AI agent"]').trigger('click');
    await findButton(wrapper, 'Second Assistant').trigger('click');
    await flushPromises();

    expect(router.currentRoute.value.params.botId).toBe('9');
    expect(lastEntriesCall()[0]).toBe(9);
  });

  it('has no bot switcher with a single bot', async () => {
    AiAgentKnowledgeAPI.getKnowledgeBases.mockResolvedValue({
      data: [knowledgeBases[0]],
    });
    const { wrapper } = await mountPage();

    expect(wrapper.find('button[aria-label="Switch AI agent"]').exists()).toBe(
      false
    );
  });

  it('opens the editor for an entry and for a new entry', async () => {
    const { wrapper } = await mountPage();

    await findButton(wrapper, 'KB-002').trigger('click');
    expect(openDialog).toHaveBeenCalledWith('KnowledgeEntryDialog', entries[1]);

    await findButton(wrapper, 'New entry').trigger('click');
    expect(openDialog).toHaveBeenLastCalledWith('KnowledgeEntryDialog');
  });

  it('asks before deleting an entry', async () => {
    const { wrapper } = await mountPage();

    await wrapper
      .findAll('button[aria-label="Delete entry"]')[0]
      .trigger('click');

    expect(openDialog).toHaveBeenCalledWith('DeleteEntryDialog', entries[0]);
  });

  it('refreshes the list after a save, a delete or an import', async () => {
    const { wrapper } = await mountPage();

    wrapper.findComponent({ name: 'KnowledgeEntryDialog' }).vm.$emit('saved');
    wrapper.findComponent({ name: 'DeleteEntryDialog' }).vm.$emit('deleted');
    wrapper
      .findComponent({ name: 'KnowledgeImportDialog' })
      .vm.$emit('imported');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.getEntries).toHaveBeenCalledTimes(4);
  });

  it('downloads the export', async () => {
    const blob = new Blob(['ID'], { type: 'text/csv' });
    AiAgentKnowledgeAPI.exportEntries.mockResolvedValue({ data: blob });
    const { wrapper } = await mountPage();

    await findButton(wrapper, 'Export').trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.exportEntries).toHaveBeenCalledWith(7);
    expect(downloadCsvFile).toHaveBeenCalledWith('knowledge-base-7.csv', blob);
  });
});
