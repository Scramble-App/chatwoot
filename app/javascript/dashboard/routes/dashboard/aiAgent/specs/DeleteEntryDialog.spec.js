import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { useAlert } from 'dashboard/composables';
import DeleteEntryDialog from '../components/DeleteEntryDialog.vue';
import { DialogStub } from './dialogStub';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    deleteEntry: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const entry = { id: 12, key: 'KB-012', question: 'What are the fees?' };

const mountDialog = async () => {
  const store = createStore({ modules: { aiAgentKnowledge } });
  const wrapper = mount(DeleteEntryDialog, {
    props: { botId: 7 },
    global: { plugins: [store], stubs: { Dialog: DialogStub } },
  });
  wrapper.vm.open(entry);
  await flushPromises();
  return wrapper;
};

describe('DeleteEntryDialog', () => {
  it('deletes the entry after confirmation', async () => {
    AiAgentKnowledgeAPI.deleteEntry.mockResolvedValue({});
    const wrapper = await mountDialog();

    expect(wrapper.find('.dialog-title').text()).toBe('Delete KB-012?');
    expect(AiAgentKnowledgeAPI.deleteEntry).not.toHaveBeenCalled();

    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.deleteEntry).toHaveBeenCalledWith(7, 12);
    expect(useAlert).toHaveBeenCalledWith('Entry deleted');
    expect(wrapper.emitted('deleted')).toHaveLength(1);
    expect(wrapper.find('.dialog-stub').exists()).toBe(false);
  });

  it('keeps the entry and says so when the delete fails', async () => {
    AiAgentKnowledgeAPI.deleteEntry.mockRejectedValue({
      response: { status: 500 },
    });
    const wrapper = await mountDialog();

    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Could not delete the entry. Please try again.'
    );
    expect(wrapper.emitted('deleted')).toBeUndefined();
  });

  it('deletes from the bot it was opened for', async () => {
    AiAgentKnowledgeAPI.deleteEntry.mockResolvedValue({});
    const wrapper = await mountDialog();

    await wrapper.setProps({ botId: 9 });
    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.deleteEntry).toHaveBeenCalledWith(7, 12);
  });

  it('keeps a reopened dialog open when an earlier delete ends', async () => {
    let finishDelete;
    AiAgentKnowledgeAPI.deleteEntry.mockReturnValue(
      new Promise(resolve => {
        finishDelete = resolve;
      })
    );
    const wrapper = await mountDialog();

    await wrapper.find('.dialog-confirm').trigger('click');
    wrapper.findComponent({ name: 'Dialog' }).vm.close();
    wrapper.vm.open({ id: 13, key: 'KB-013' });
    await flushPromises();
    finishDelete({});
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Entry deleted');
    expect(wrapper.emitted('deleted')).toHaveLength(1);
    expect(wrapper.find('.dialog-title').text()).toBe('Delete KB-013?');
    expect(
      wrapper.find('.dialog-confirm').attributes('disabled')
    ).toBeUndefined();
  });
});
