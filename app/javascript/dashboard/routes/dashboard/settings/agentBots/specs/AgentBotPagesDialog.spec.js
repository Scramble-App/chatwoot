import { mount, flushPromises } from '@vue/test-utils';
import AgentBotPagesDialog from '../components/AgentBotPagesDialog.vue';
import AgentBotsAPI from 'dashboard/api/agentBots';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/agentBots', () => ({
  default: {
    getPages: vi.fn(),
    createPage: vi.fn(),
    deletePage: vi.fn(),
    refreshPage: vi.fn(),
  },
}));

const openDialog = vi.fn();
const bot = { id: 5, name: 'Assistant' };
const NOW = Math.floor(Date.now() / 1000);

const PAGES = [
  {
    id: 7,
    url: 'https://example.com/pricing',
    title: 'Pricing',
    status: 'fetched',
    error_message: null,
    fetched_at: NOW - 3 * 60 * 60,
    content_length: 1200,
  },
  {
    id: 8,
    url: 'https://example.com/new',
    title: null,
    status: 'pending',
    error_message: null,
    fetched_at: null,
    content_length: 0,
  },
  {
    id: 9,
    url: 'https://example.com/gone',
    title: 'Gone',
    status: 'failed',
    error_message: 'The page returned 404',
    fetched_at: null,
    content_length: 0,
  },
];

const mountDialog = async () => {
  const wrapper = mount(AgentBotPagesDialog, {
    global: {
      stubs: {
        Dialog: {
          props: ['title', 'description'],
          template:
            '<div><h3>{{ title }}</h3><p>{{ description }}</p><slot /></div>',
          methods: { open: openDialog, close() {} },
        },
      },
    },
  });
  wrapper.vm.open(bot);
  await flushPromises();
  return wrapper;
};

const pageRows = wrapper => wrapper.findAll('[data-test-id="agent-bot-page"]');

const addPage = async (wrapper, url) => {
  await wrapper.find('#agent-bot-page-url').setValue(url);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('AgentBotPagesDialog.vue', () => {
  beforeEach(() => {
    AgentBotsAPI.getPages.mockResolvedValue({ data: PAGES });
    AgentBotsAPI.createPage.mockResolvedValue({ data: {} });
    AgentBotsAPI.deletePage.mockResolvedValue({ data: {} });
    AgentBotsAPI.refreshPage.mockResolvedValue({ data: {} });
  });

  it('lists the pages of the bot with their status, fetch time and error', async () => {
    const wrapper = await mountDialog();

    expect(openDialog).toHaveBeenCalled();
    expect(AgentBotsAPI.getPages).toHaveBeenCalledWith(5);
    expect(wrapper.text()).toContain('Assistant can open these pages');

    const [fetched, pending, failed] = pageRows(wrapper);
    expect(fetched.text()).toContain('Pricing');
    expect(fetched.find('a').attributes('href')).toBe(
      'https://example.com/pricing'
    );
    expect(fetched.text()).toContain('Fetched');
    expect(fetched.text()).toContain('Last fetched about 3 hours ago');

    expect(pending.text()).toContain('https://example.com/new');
    expect(pending.text()).toContain('Fetching');
    expect(pending.text()).not.toContain('Last fetched');

    expect(failed.text()).toContain('Failed');
    expect(failed.text()).toContain('The page returned 404');
  });

  it('reads the pages from a payload too', async () => {
    AgentBotsAPI.getPages.mockResolvedValue({ data: { payload: [PAGES[0]] } });
    const wrapper = await mountDialog();

    expect(pageRows(wrapper)).toHaveLength(1);
  });

  it('shows an empty state when the bot has no pages', async () => {
    AgentBotsAPI.getPages.mockResolvedValue({ data: [] });
    const wrapper = await mountDialog();

    expect(pageRows(wrapper)).toHaveLength(0);
    expect(wrapper.text()).toContain('No pages yet');
  });

  it.each([
    'example.com/pricing',
    'ftp://example.com/file',
    'mailto:team@example.com',
  ])('does not add %s', async url => {
    const wrapper = await mountDialog();

    await addPage(wrapper, url);

    expect(AgentBotsAPI.createPage).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'Enter a page URL that starts with http:// or https://'
    );
  });

  it('adds a page and lists it again', async () => {
    const wrapper = await mountDialog();

    await addPage(wrapper, '  https://example.com/faq  ');

    expect(AgentBotsAPI.createPage).toHaveBeenCalledWith(
      5,
      'https://example.com/faq'
    );
    expect(AgentBotsAPI.getPages).toHaveBeenCalledTimes(2);
    expect(wrapper.find('#agent-bot-page-url').element.value).toBe('');
  });

  it('shows why the page could not be added', async () => {
    AgentBotsAPI.createPage.mockRejectedValue({
      response: { data: { message: 'Url has already been taken' } },
    });
    const wrapper = await mountDialog();

    await addPage(wrapper, 'https://example.com/pricing');

    expect(wrapper.text()).toContain('Url has already been taken');
    expect(wrapper.find('#agent-bot-page-url').element.value).toBe(
      'https://example.com/pricing'
    );
  });

  it('fetches a page again', async () => {
    const wrapper = await mountDialog();

    await pageRows(wrapper)[0]
      .find('[data-test-id="agent-bot-page-refresh"]')
      .trigger('click');
    await flushPromises();

    expect(AgentBotsAPI.refreshPage).toHaveBeenCalledWith(5, 7);
    expect(useAlert).toHaveBeenCalledWith(
      'The page will be fetched again shortly.'
    );
    expect(AgentBotsAPI.getPages).toHaveBeenCalledTimes(2);
  });

  it('removes a page only after the confirmation', async () => {
    const wrapper = await mountDialog();
    const deleteButton = pageRows(wrapper)[2].find(
      '[data-test-id="agent-bot-page-delete"] button'
    );

    await deleteButton.trigger('click');
    expect(AgentBotsAPI.deletePage).not.toHaveBeenCalled();
    expect(deleteButton.text()).toContain('Remove');

    await deleteButton.trigger('click');
    await flushPromises();

    expect(AgentBotsAPI.deletePage).toHaveBeenCalledWith(5, 9);
    expect(pageRows(wrapper)).toHaveLength(2);
    expect(wrapper.text()).not.toContain('The page returned 404');
  });

  it('reloads the list to show new statuses', async () => {
    const wrapper = await mountDialog();
    AgentBotsAPI.getPages.mockResolvedValue({
      data: [{ ...PAGES[1], status: 'fetched', fetched_at: NOW }],
    });

    await wrapper
      .find('[data-test-id="agent-bot-pages-reload"]')
      .trigger('click');
    await flushPromises();

    expect(pageRows(wrapper)).toHaveLength(1);
    expect(pageRows(wrapper)[0].text()).toContain('Fetched');
  });
});
