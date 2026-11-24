import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentBotModal from '../components/AgentBotModal.vue';
import AgentBotsAPI from 'dashboard/api/agentBots';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/agentBots', () => ({
  default: { getAiAgentDefaults: vi.fn() },
}));

const dispatch = vi.fn();
const closeDialog = vi.fn();

const DEFAULTS = {
  model: 'gpt-test-model',
  reasoning_effort: 'low',
  tone_of_voice: 'Warm and plain.',
  instructions: 'Answer first.\nOffer more detail.',
  fallback_message: 'Passing you to the team.',
  max_replies_per_conversation: 30,
};

const TEAMS = [
  { id: 2, name: 'Brands' },
  { id: 3, name: 'Partners' },
];

const aiAgentBot = {
  id: 9,
  name: 'Assistant',
  description: 'Answers founders',
  bot_type: 'ai_agent',
  outgoing_url: null,
  thumbnail: '',
  access_token: 'token-value',
  secret: 'secret-value',
  bot_config: {
    model: 'gpt-custom',
    reasoning_effort: 'medium',
    tone_of_voice: 'Short and friendly.',
    instructions: '',
    handoff_team_id: '2',
    max_replies_per_conversation: '40',
    fallback_message: '',
  },
};

const DialogStub = {
  template: '<div><slot /></div>',
  emits: ['close'],
  methods: { open() {}, close: closeDialog },
};

const mountModal = (props = {}) =>
  mount(AgentBotModal, {
    props,
    global: {
      stubs: {
        Dialog: DialogStub,
        Avatar: true,
        AccessToken: { template: '<div class="access-token" />' },
      },
    },
  });

const chooseAiAgent = async wrapper => {
  await wrapper.find('#agent-bot-type-ai_agent').setChecked();
  await flushPromises();
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

const teamSelect = wrapper =>
  wrapper.find('[data-test-id="bot-handoff-team"] select');

describe('AgentBotModal.vue', () => {
  beforeEach(() => {
    dispatch.mockResolvedValue({});
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(getter => {
      if (getter === 'teams/getTeams') return ref(TEAMS);
      return ref({ isCreating: false, isUpdating: false });
    });
    AgentBotsAPI.getAiAgentDefaults.mockResolvedValue({ data: DEFAULTS });
  });

  describe('webhook bots', () => {
    it('keeps the webhook URL and sends the same payload as before', async () => {
      const wrapper = mountModal();

      expect(wrapper.find('#bot-url').exists()).toBe(true);
      expect(wrapper.find('#bot-model').exists()).toBe(false);

      await wrapper.find('#bot-name').setValue('Support bot');
      await wrapper.find('#bot-url').setValue('https://example.com/hook');
      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith('agentBots/create', {
        name: 'Support bot',
        description: '',
        outgoing_url: 'https://example.com/hook',
        bot_type: 'webhook',
        avatar: null,
      });
      expect(AgentBotsAPI.getAiAgentDefaults).not.toHaveBeenCalled();
    });

    it('requires the webhook URL', async () => {
      const wrapper = mountModal();

      await wrapper.find('#bot-name').setValue('Support bot');
      await submit(wrapper);

      expect(dispatch).not.toHaveBeenCalledWith(
        'agentBots/create',
        expect.anything()
      );
    });
  });

  describe('AI agent bots', () => {
    it('hides the webhook URL and shows the settings with their defaults', async () => {
      const wrapper = mountModal();

      await chooseAiAgent(wrapper);

      expect(wrapper.find('#bot-url').exists()).toBe(false);
      expect(AgentBotsAPI.getAiAgentDefaults).toHaveBeenCalledTimes(1);
      expect(dispatch).toHaveBeenCalledWith('teams/get');
      expect(wrapper.find('#bot-model').attributes('placeholder')).toBe(
        'gpt-test-model'
      );
      expect(wrapper.find('#bot-tone-of-voice').attributes('placeholder')).toBe(
        'Warm and plain.'
      );
      expect(wrapper.find('#bot-instructions').attributes('placeholder')).toBe(
        'Answer first.\nOffer more detail.'
      );
      expect(
        wrapper.find('#bot-fallback-message').attributes('placeholder')
      ).toBe('Passing you to the team.');
      expect(wrapper.find('#bot-reply-limit').attributes('placeholder')).toBe(
        '30'
      );
      const teamOptions = wrapper
        .findAll('[data-test-id="bot-handoff-team"] option')
        .map(option => option.text());
      expect(teamOptions).toEqual(['None', 'Brands', 'Partners']);
    });

    it('hints at the OpenAI integration model when it has none', async () => {
      AgentBotsAPI.getAiAgentDefaults.mockResolvedValue({
        data: { ...DEFAULTS, model: null },
      });
      const wrapper = mountModal();

      await chooseAiAgent(wrapper);

      expect(wrapper.find('#bot-model').attributes('placeholder')).toBe(
        'OpenAI integration model'
      );
    });

    it('sends every setting, with blank ones as empty values', async () => {
      const wrapper = mountModal();

      await chooseAiAgent(wrapper);
      await wrapper.find('#bot-name').setValue('Assistant');
      await wrapper.find('#bot-model').setValue('  gpt-other  ');
      await wrapper.find('#bot-instructions').setValue('Keep it short.\n');
      await wrapper
        .find('[data-test-id="bot-handoff-team"] select')
        .setValue(3);
      await wrapper.find('#bot-reply-limit').setValue('25');
      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith('agentBots/create', {
        name: 'Assistant',
        description: '',
        outgoing_url: '',
        bot_type: 'ai_agent',
        avatar: null,
        bot_config: {
          model: 'gpt-other',
          reasoning_effort: '',
          tone_of_voice: '',
          instructions: 'Keep it short.',
          handoff_team_id: 3,
          max_replies_per_conversation: 25,
          fallback_message: '',
        },
      });
      expect(closeDialog).toHaveBeenCalled();
      expect(wrapper.find('.access-token').exists()).toBe(false);
    });

    it('copies the default text in, and does not save it as an override', async () => {
      const wrapper = mountModal();

      await chooseAiAgent(wrapper);
      await wrapper.find('#bot-name').setValue('Assistant');
      const [useToneDefault] = wrapper.findAll(
        '[data-test-id="ai-agent-text-setting-use-default"]'
      );
      await useToneDefault.trigger('click');

      expect(wrapper.find('#bot-tone-of-voice').element.value).toBe(
        'Warm and plain.'
      );

      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith(
        'agentBots/create',
        expect.objectContaining({
          bot_config: expect.objectContaining({ tone_of_voice: '' }),
        })
      );
    });

    it.each(['0', '201', '2.5'])(
      'rejects %s as the reply limit',
      async value => {
        const wrapper = mountModal();

        await chooseAiAgent(wrapper);
        await wrapper.find('#bot-name').setValue('Assistant');
        await wrapper.find('#bot-reply-limit').setValue(value);
        await submit(wrapper);

        expect(dispatch).not.toHaveBeenCalledWith(
          'agentBots/create',
          expect.anything()
        );
        expect(wrapper.text()).toContain('Enter a whole number from 1 to 200');
      }
    );

    it('edits a bot with its saved settings and keeps the hidden ones', async () => {
      const wrapper = mountModal({ type: 'edit', selectedBot: aiAgentBot });
      await flushPromises();

      expect(wrapper.find('#agent-bot-type-ai_agent').element.checked).toBe(
        true
      );
      expect(wrapper.find('#bot-model').element.value).toBe('gpt-custom');
      expect(wrapper.find('#bot-tone-of-voice').element.value).toBe(
        'Short and friendly.'
      );
      expect(
        wrapper.find('[data-test-id="bot-handoff-team"] select').element.value
      ).toBe('2');
      expect(wrapper.find('#bot-reply-limit').element.value).toBe('40');
      // The webhook secret means nothing for an AI agent bot
      expect(wrapper.text()).not.toContain('Webhook Secret');

      await wrapper.find('#bot-tone-of-voice').setValue('');
      await wrapper
        .find('[data-test-id="bot-handoff-team"] select')
        .setValue('');
      await wrapper.find('#bot-reply-limit').setValue('');
      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith('agentBots/update', {
        id: 9,
        data: {
          name: 'Assistant',
          description: 'Answers founders',
          outgoing_url: '',
          bot_type: 'ai_agent',
          avatar: null,
          bot_config: {
            model: 'gpt-custom',
            reasoning_effort: 'medium',
            tone_of_voice: '',
            instructions: '',
            handoff_team_id: null,
            max_replies_per_conversation: null,
            fallback_message: '',
          },
        },
      });
    });

    it('sends only the AI agent keys when a webhook bot becomes an AI agent', async () => {
      const webhookBot = {
        id: 4,
        name: 'Legacy bot',
        description: '',
        bot_type: 'webhook',
        outgoing_url: 'https://example.com/hook',
        bot_config: { webhook_url: 'https://example.com/old-hook' },
      };
      const wrapper = mountModal({ type: 'edit', selectedBot: webhookBot });

      await chooseAiAgent(wrapper);
      await submit(wrapper);

      const [, { data }] = dispatch.mock.calls.find(
        ([action]) => action === 'agentBots/update'
      );
      expect(data.outgoing_url).toBe('');
      expect(Object.keys(data.bot_config).sort()).toEqual([
        'fallback_message',
        'handoff_team_id',
        'instructions',
        'max_replies_per_conversation',
        'model',
        'reasoning_effort',
        'tone_of_voice',
      ]);
    });

    it('turns an AI agent bot back into a webhook bot without its settings', async () => {
      const wrapper = mountModal({ type: 'edit', selectedBot: aiAgentBot });
      await flushPromises();

      await wrapper.find('#agent-bot-type-webhook').setChecked();
      await wrapper.find('#bot-url').setValue('https://example.com/hook');
      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith('agentBots/update', {
        id: 9,
        data: {
          name: 'Assistant',
          description: 'Answers founders',
          outgoing_url: 'https://example.com/hook',
          bot_type: 'webhook',
          avatar: null,
        },
      });
    });

    it('sends the saved settings back as numbers when the API returns strings', async () => {
      const wrapper = mountModal({ type: 'edit', selectedBot: aiAgentBot });
      await flushPromises();

      await submit(wrapper);

      expect(dispatch).toHaveBeenCalledWith(
        'agentBots/update',
        expect.objectContaining({
          data: expect.objectContaining({
            bot_config: expect.objectContaining({
              handoff_team_id: 2,
              max_replies_per_conversation: 40,
            }),
          }),
        })
      );
    });

    describe('when the saved handoff team was deleted', () => {
      const botWithDeletedTeam = {
        ...aiAgentBot,
        bot_config: { ...aiAgentBot.bot_config, handoff_team_id: '99' },
      };
      const savedTeamId = () =>
        dispatch.mock.calls.find(([action]) => action === 'agentBots/update')[1]
          .data.bot_config.handoff_team_id;

      it('shows and saves None once the teams have loaded', async () => {
        const wrapper = mountModal({
          type: 'edit',
          selectedBot: botWithDeletedTeam,
        });
        await flushPromises();

        expect(teamSelect(wrapper).element.value).toBe('');

        await submit(wrapper);

        expect(savedTeamId()).toBeNull();
      });

      it.each([
        ['are still loading', () => new Promise(() => {})],
        ['could not be loaded', () => Promise.reject(new Error('Offline'))],
      ])('keeps it while the teams %s', async (_, getTeams) => {
        dispatch.mockImplementation(action =>
          action === 'teams/get' ? getTeams() : Promise.resolve({})
        );
        const wrapper = mountModal({
          type: 'edit',
          selectedBot: botWithDeletedTeam,
        });
        await flushPromises();

        await submit(wrapper);

        expect(savedTeamId()).toBe(99);
      });
    });
  });

  describe('the form', () => {
    it('groups the bot types as labelled radios with one name', () => {
      const wrapper = mountModal();
      const group = wrapper.find('[role="radiogroup"]');

      expect(
        wrapper.find(`#${group.attributes('aria-labelledby')}`).text()
      ).toBe('Bot type');
      expect(
        group
          .findAll('input[type="radio"]')
          .map(radio => radio.attributes('name'))
      ).toEqual(['agent-bot-type', 'agent-bot-type']);
    });

    it('limits the model name to 255 characters', async () => {
      const wrapper = mountModal();

      await chooseAiAgent(wrapper);

      expect(wrapper.find('#bot-model').attributes('maxlength')).toBe('255');
    });

    it('shows why the API refused to save the bot', async () => {
      dispatch.mockImplementation(action =>
        action === 'agentBots/update'
          ? Promise.reject(new Error('Bot config has unknown keys: colour'))
          : Promise.resolve({})
      );
      const wrapper = mountModal({ type: 'edit', selectedBot: aiAgentBot });
      await flushPromises();

      await submit(wrapper);

      expect(useAlert).toHaveBeenCalledWith(
        'Bot config has unknown keys: colour'
      );
      expect(closeDialog).not.toHaveBeenCalled();
    });

    it('falls back to the generic error when the API gives no reason', async () => {
      dispatch.mockImplementation(action =>
        action === 'agentBots/create'
          ? Promise.reject(new Error(''))
          : Promise.resolve({})
      );
      const wrapper = mountModal();

      await wrapper.find('#bot-name').setValue('Support bot');
      await wrapper.find('#bot-url').setValue('https://example.com/hook');
      await submit(wrapper);

      expect(useAlert).toHaveBeenCalledWith(
        'Could not add bot. Please try again later.'
      );
    });

    it('drops unsaved edits when it is closed', async () => {
      const wrapper = mountModal({ type: 'edit', selectedBot: aiAgentBot });
      await flushPromises();
      await wrapper.find('#bot-name').setValue('Unsaved name');
      await wrapper.find('#bot-model').setValue('unsaved-model');

      wrapper.findComponent(DialogStub).vm.$emit('close');
      await flushPromises();

      expect(wrapper.find('#bot-name').element.value).toBe('Assistant');
      expect(wrapper.find('#bot-model').element.value).toBe('gpt-custom');
    });
  });
});
