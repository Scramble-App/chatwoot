import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import KnowledgeEntryDialog from '../components/KnowledgeEntryDialog.vue';
import { DialogStub } from './dialogStub';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    showEntry: vi.fn(),
    createEntry: vi.fn(),
    updateEntry: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const needsAnswerEntry = {
  id: 2,
  key: 'KB-002',
  category: 'Eligibility',
  frequency: 'Rare',
  question: 'Do you fund brands outside the EU?',
  alternative_questions: 'Can a UK brand apply?',
  short_answer: null,
  answer: null,
  selling_point: null,
  status: 'needs_answer',
  asked_count: 2,
};

const mountDialog = async () => {
  const store = createStore({ modules: { aiAgentKnowledge } });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/ai-agent/:botId/knowledge',
        name: 'ai_agent_knowledge',
        component: { template: '<div />' },
      },
      {
        path: '/app/accounts/:accountId/conversations/:conversation_id',
        name: 'inbox_conversation',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/app/accounts/1/ai-agent/7/knowledge');
  await router.isReady();

  return mount(KnowledgeEntryDialog, {
    props: { botId: 7, categories: ['Pricing', 'Eligibility'] },
    global: { plugins: [store, router], stubs: { Dialog: DialogStub } },
  });
};

const textArea = (wrapper, id) =>
  wrapper.findAllComponents(TextArea).find(area => area.props('id') === id);

const fill = async (wrapper, values) => {
  const [key, category, frequency] = wrapper.findAllComponents(Input);
  const inputs = { key, category, frequency };
  await Object.entries(values).reduce(async (previous, [field, value]) => {
    await previous;
    if (inputs[field]) {
      await inputs[field].find('input').setValue(value);
    } else if (field === 'status') {
      await wrapper.find('select').setValue(value);
    } else {
      await wrapper
        .find(`#ai-agent-entry-${field.replace(/_/g, '-')}`)
        .setValue(value);
    }
  }, Promise.resolve());
};

const confirmButton = wrapper => wrapper.find('.dialog-confirm');

const closeDialog = wrapper =>
  wrapper.findComponent({ name: 'Dialog' }).vm.close();

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

describe('KnowledgeEntryDialog', () => {
  it('creates an entry with trimmed fields and one phrasing per line', async () => {
    AiAgentKnowledgeAPI.createEntry.mockResolvedValue({ data: { id: 5 } });
    const wrapper = await mountDialog();

    wrapper.vm.open();
    await flushPromises();
    expect(wrapper.find('.dialog-title').text()).toBe('New entry');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();

    await fill(wrapper, {
      category: ' Pricing ',
      question: '  How long does a review take?  ',
      alternative_questions:
        'How fast is the review?\n\n  When do I hear back? \n',
      short_answer: 'About two weeks.',
      status: 'published',
    });
    expect(confirmButton(wrapper).attributes('disabled')).toBeUndefined();

    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.createEntry).toHaveBeenCalledWith(7, {
      key: '',
      category: 'Pricing',
      frequency: '',
      question: 'How long does a review take?',
      alternative_questions: 'How fast is the review?\nWhen do I hear back?',
      short_answer: 'About two weeks.',
      answer: '',
      selling_point: '',
      status: 'published',
    });
    expect(useAlert).toHaveBeenCalledWith('Entry added');
    expect(wrapper.emitted('saved')).toHaveLength(1);
    expect(wrapper.find('.dialog-stub').exists()).toBe(false);
  });

  it('edits an entry and shows the latest customer wordings', async () => {
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({
      data: {
        ...needsAnswerEntry,
        questions: [
          {
            id: 31,
            content: 'Hi, we are a Swiss brand, can we apply?',
            conversation_id: 321,
            created_at: 1700000000,
          },
        ],
      },
    });
    AiAgentKnowledgeAPI.updateEntry.mockResolvedValue({ data: {} });
    const wrapper = await mountDialog();

    wrapper.vm.open(needsAnswerEntry);
    await flushPromises();

    expect(wrapper.find('.dialog-title').text()).toBe('Edit KB-002');
    expect(AiAgentKnowledgeAPI.showEntry).toHaveBeenCalledWith(7, 2);
    expect(wrapper.find('#ai-agent-entry-question').element.value).toBe(
      'Do you fund brands outside the EU?'
    );
    expect(wrapper.text()).toContain('Latest customer wordings');
    expect(wrapper.text()).toContain('Hi, we are a Swiss brand, can we apply?');
    const link = wrapper.find('a[href="/app/accounts/1/conversations/321"]');
    expect(link.text()).toBe('Conversation #321');

    await fill(wrapper, { answer: 'Yes, across Europe.', status: 'published' });
    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.updateEntry).toHaveBeenCalledWith(7, 2, {
      key: 'KB-002',
      category: 'Eligibility',
      frequency: 'Rare',
      question: 'Do you fund brands outside the EU?',
      alternative_questions: 'Can a UK brand apply?',
      short_answer: '',
      answer: 'Yes, across Europe.',
      selling_point: '',
      status: 'published',
    });
    expect(useAlert).toHaveBeenCalledWith('Entry saved');
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('shows the validation errors of the API and marks the fields', async () => {
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({
      data: { ...needsAnswerEntry, questions: [] },
    });
    AiAgentKnowledgeAPI.updateEntry.mockRejectedValue({
      response: {
        status: 422,
        data: {
          message: 'Key has already been taken',
          attributes: ['key'],
        },
      },
    });
    const wrapper = await mountDialog();

    wrapper.vm.open(needsAnswerEntry);
    await flushPromises();
    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Key has already been taken'
    );
    const [keyInput, categoryInput] = wrapper.findAllComponents(Input);
    expect(keyInput.props('messageType')).toBe('error');
    expect(categoryInput.props('messageType')).toBe('info');
    expect(
      textArea(wrapper, 'ai-agent-entry-question').props('messageType')
    ).toBe('info');
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(wrapper.find('.dialog-stub').exists()).toBe(true);
  });

  it('falls back to a generic error when the API gives no message', async () => {
    AiAgentKnowledgeAPI.createEntry.mockRejectedValue(new Error('Network'));
    const wrapper = await mountDialog();

    wrapper.vm.open();
    await flushPromises();
    await fill(wrapper, { question: 'What are the fees?' });
    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Could not save the entry. Please try again.'
    );
  });

  it('hints that a published entry needs an answer', async () => {
    const wrapper = await mountDialog();

    wrapper.vm.open();
    await flushPromises();
    const hint = 'A published entry needs a short or a full answer.';
    expect(wrapper.text()).not.toContain(hint);

    await fill(wrapper, { status: 'published' });
    expect(wrapper.text()).toContain(hint);

    await fill(wrapper, { answer: 'We charge a flat fee.' });
    expect(wrapper.text()).not.toContain(hint);
  });

  it('opens a new entry with empty fields after editing one', async () => {
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({
      data: { ...needsAnswerEntry, questions: [] },
    });
    const wrapper = await mountDialog();

    wrapper.vm.open(needsAnswerEntry);
    await flushPromises();
    wrapper.vm.open();
    await flushPromises();

    expect(wrapper.find('.dialog-title').text()).toBe('New entry');
    expect(wrapper.find('#ai-agent-entry-question').element.value).toBe('');
    expect(wrapper.find('select').element.value).toBe('draft');
  });

  it('keeps saving to the bot it was opened for', async () => {
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({
      data: { ...needsAnswerEntry, questions: [] },
    });
    AiAgentKnowledgeAPI.updateEntry.mockResolvedValue({ data: {} });
    const wrapper = await mountDialog();

    wrapper.vm.open(needsAnswerEntry);
    await flushPromises();
    await wrapper.setProps({ botId: 9 });
    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.showEntry).toHaveBeenCalledWith(7, 2);
    expect(AiAgentKnowledgeAPI.updateEntry).toHaveBeenCalledWith(
      7,
      2,
      expect.objectContaining({ key: 'KB-002' })
    );
  });

  it('keeps a reopened dialog open when an earlier save ends', async () => {
    const pendingSave = deferred();
    AiAgentKnowledgeAPI.createEntry.mockReturnValue(pendingSave.promise);
    AiAgentKnowledgeAPI.showEntry.mockResolvedValue({
      data: { ...needsAnswerEntry, questions: [] },
    });
    const wrapper = await mountDialog();

    wrapper.vm.open();
    await flushPromises();
    await fill(wrapper, { question: 'What are the fees?' });
    await confirmButton(wrapper).trigger('click');
    closeDialog(wrapper);
    wrapper.vm.open(needsAnswerEntry);
    await flushPromises();
    pendingSave.resolve({ data: { id: 5 } });
    await flushPromises();

    // The first entry was saved, so the list still refreshes
    expect(useAlert).toHaveBeenCalledWith('Entry added');
    expect(wrapper.emitted('saved')).toHaveLength(1);
    expect(wrapper.find('.dialog-title').text()).toBe('Edit KB-002');
    expect(confirmButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('keeps the errors of an earlier save out of a reopened dialog', async () => {
    const pendingSave = deferred();
    AiAgentKnowledgeAPI.createEntry.mockReturnValue(pendingSave.promise);
    const wrapper = await mountDialog();

    wrapper.vm.open();
    await flushPromises();
    await fill(wrapper, { question: 'What are the fees?' });
    await confirmButton(wrapper).trigger('click');
    closeDialog(wrapper);
    wrapper.vm.open();
    await flushPromises();
    pendingSave.reject({
      response: {
        status: 422,
        data: { message: 'Key has already been taken', attributes: ['key'] },
      },
    });
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.findAllComponents(Input)[0].props('messageType')).toBe(
      'info'
    );
  });

  it('drops customer wordings that arrive after the dialog was reopened', async () => {
    const pendingShow = deferred();
    AiAgentKnowledgeAPI.showEntry.mockReturnValue(pendingShow.promise);
    const wrapper = await mountDialog();

    wrapper.vm.open(needsAnswerEntry);
    closeDialog(wrapper);
    wrapper.vm.open();
    await flushPromises();
    pendingShow.resolve({
      data: {
        ...needsAnswerEntry,
        questions: [
          {
            id: 31,
            content: 'Can a Swiss brand apply?',
            conversation_id: 321,
            created_at: 1700000000,
          },
        ],
      },
    });
    await flushPromises();

    expect(wrapper.text()).not.toContain('Latest customer wordings');
  });
});
