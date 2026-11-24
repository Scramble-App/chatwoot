import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import aiAgentKnowledge from 'dashboard/store/modules/aiAgentKnowledge';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { useAlert } from 'dashboard/composables';
import KnowledgeImportDialog from '../components/KnowledgeImportDialog.vue';
import { DialogStub } from './dialogStub';

vi.mock('dashboard/api/aiAgentKnowledge', () => ({
  default: {
    importEntries: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const file = new File(['ID,Вопрос\nKB-001,Fees?'], 'knowledge.csv', {
  type: 'text/csv',
});

const mountDialog = async () => {
  const store = createStore({ modules: { aiAgentKnowledge } });
  const wrapper = mount(KnowledgeImportDialog, {
    props: { botId: 7 },
    global: { plugins: [store], stubs: { Dialog: DialogStub } },
  });
  wrapper.vm.open();
  await flushPromises();
  return wrapper;
};

const chooseFile = async wrapper => {
  const input = wrapper.find('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [file],
    configurable: true,
  });
  await input.trigger('change');
  await flushPromises();
};

const confirmButton = wrapper => wrapper.find('.dialog-confirm');

describe('KnowledgeImportDialog', () => {
  it('opens the file picker from the button', async () => {
    const wrapper = await mountDialog();
    const input = wrapper.find('input[type="file"]');
    const click = vi.spyOn(input.element, 'click');

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Choose CSV file')
      .trigger('click');

    expect(click).toHaveBeenCalled();
    expect(input.attributes('accept')).toBe('.csv,text/csv');
  });

  it('checks the file with a dry run, then imports it after confirming', async () => {
    AiAgentKnowledgeAPI.importEntries
      .mockResolvedValueOnce({ data: { created: 2, updated: 1, errors: [] } })
      .mockResolvedValueOnce({ data: { created: 2, updated: 1, errors: [] } });
    const wrapper = await mountDialog();
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();

    await chooseFile(wrapper);

    expect(AiAgentKnowledgeAPI.importEntries).toHaveBeenCalledWith(7, {
      file,
      dryRun: true,
    });
    expect(wrapper.text()).toContain('knowledge.csv');
    expect(wrapper.text()).toContain('New entries');
    expect(wrapper.text()).toContain('Updated entries');
    expect(confirmButton(wrapper).attributes('disabled')).toBeUndefined();
    expect(wrapper.emitted('imported')).toBeUndefined();

    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(AiAgentKnowledgeAPI.importEntries).toHaveBeenLastCalledWith(7, {
      file,
      dryRun: false,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Import finished: 2 added, 1 updated'
    );
    expect(wrapper.emitted('imported')).toHaveLength(1);
    expect(wrapper.find('.dialog-stub').exists()).toBe(false);
  });

  it('lists the row errors of the dry run and blocks the import', async () => {
    AiAgentKnowledgeAPI.importEntries.mockResolvedValue({
      data: {
        created: 1,
        updated: 0,
        errors: [
          { row: 3, message: "Question can't be blank" },
          { row: 7, message: 'Status is not included in the list' },
        ],
      },
    });
    const wrapper = await mountDialog();

    await chooseFile(wrapper);

    const text = wrapper.text();
    expect(text).toContain('2 rows need fixing');
    expect(text).toContain("Row 3: Question can't be blank");
    expect(text).toContain('Row 7: Status is not included in the list');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('shows the row errors when the import is refused with a 422', async () => {
    AiAgentKnowledgeAPI.importEntries
      .mockResolvedValueOnce({ data: { created: 1, updated: 0, errors: [] } })
      .mockRejectedValueOnce({
        response: {
          status: 422,
          data: { errors: [{ row: 2, message: 'Key has already been taken' }] },
        },
      });
    const wrapper = await mountDialog();

    await chooseFile(wrapper);
    await confirmButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Row 2: Key has already been taken');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('imported')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('shows a file error without a row', async () => {
    AiAgentKnowledgeAPI.importEntries.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'The file is larger than 5 MB' },
      },
    });
    const wrapper = await mountDialog();

    await chooseFile(wrapper);

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'The file is larger than 5 MB'
    );
    expect(wrapper.text()).not.toContain('New entries');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('says when the file has nothing to import', async () => {
    AiAgentKnowledgeAPI.importEntries.mockResolvedValue({
      data: { created: 0, updated: 0, errors: [] },
    });
    const wrapper = await mountDialog();

    await chooseFile(wrapper);

    expect(wrapper.text()).toContain('The file has no entries to import.');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('starts over when it is opened again', async () => {
    AiAgentKnowledgeAPI.importEntries.mockResolvedValue({
      data: { created: 1, updated: 0, errors: [] },
    });
    const wrapper = await mountDialog();
    await chooseFile(wrapper);

    wrapper.vm.open();
    await flushPromises();

    expect(wrapper.text()).not.toContain('knowledge.csv');
    expect(wrapper.text()).not.toContain('New entries');
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
  });
});
