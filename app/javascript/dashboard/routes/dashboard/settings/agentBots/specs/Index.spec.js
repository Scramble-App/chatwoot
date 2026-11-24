import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import Index from '../Index.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router');

const dispatch = vi.fn();
const push = vi.fn();
const openPages = vi.fn();

const BOTS = [
  {
    id: 1,
    name: 'Webhook helper',
    description: '',
    bot_type: 'webhook',
    outgoing_url: 'https://example.com/hook',
    bot_config: {},
    system_bot: false,
  },
  {
    id: 2,
    name: 'Assistant',
    description: '',
    bot_type: 'ai_agent',
    outgoing_url: null,
    bot_config: {},
    system_bot: false,
  },
];

const mountIndex = () =>
  mount(Index, {
    global: {
      stubs: {
        BaseSettingsHeader: true,
        WootLoadingState: true,
        Avatar: true,
        AgentBotModal: true,
        Dialog: true,
        AgentBotPagesDialog: {
          template: '<div />',
          methods: { open: openPages },
        },
      },
    },
  });

const rowOf = (wrapper, name) =>
  wrapper.findAll('tbody tr').find(row => row.text().includes(name));

describe('agent bots Index.vue', () => {
  beforeEach(() => {
    dispatch.mockResolvedValue({});
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(getter => {
      if (getter === 'agentBots/getBots') return ref(BOTS);
      return ref({ isFetching: false, isDeleting: false });
    });
    useRoute.mockReturnValue({ params: { accountId: '4' } });
    useRouter.mockReturnValue({ push });
  });

  it('shows the type of each bot', () => {
    const wrapper = mountIndex();

    const webhookRow = rowOf(wrapper, 'Webhook helper');
    expect(webhookRow.find('[data-test-id="agent-bot-type"]').text()).toBe(
      'Webhook'
    );
    expect(webhookRow.text()).toContain('https://example.com/hook');
    expect(
      rowOf(wrapper, 'Assistant').find('[data-test-id="agent-bot-type"]').text()
    ).toBe('AI agent');
  });

  it('offers pages and the knowledge base for AI agent bots only', () => {
    const wrapper = mountIndex();

    const webhookRow = rowOf(wrapper, 'Webhook helper');
    expect(webhookRow.find('[data-test-id="agent-bot-pages"]').exists()).toBe(
      false
    );
    expect(
      webhookRow.find('[data-test-id="agent-bot-knowledge-base"]').exists()
    ).toBe(false);

    const aiAgentRow = rowOf(wrapper, 'Assistant');
    expect(aiAgentRow.find('[data-test-id="agent-bot-pages"]').exists()).toBe(
      true
    );
    expect(
      aiAgentRow.find('[data-test-id="agent-bot-knowledge-base"]').exists()
    ).toBe(true);
  });

  it('opens the pages of the bot', async () => {
    const wrapper = mountIndex();

    await rowOf(wrapper, 'Assistant')
      .find('[data-test-id="agent-bot-pages"]')
      .trigger('click');

    expect(openPages).toHaveBeenCalledWith(BOTS[1]);
  });

  it('opens the knowledge base of the bot', async () => {
    const wrapper = mountIndex();

    await rowOf(wrapper, 'Assistant')
      .find('[data-test-id="agent-bot-knowledge-base"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'ai_agent_knowledge',
      params: { accountId: '4', botId: 2 },
    });
  });
});
