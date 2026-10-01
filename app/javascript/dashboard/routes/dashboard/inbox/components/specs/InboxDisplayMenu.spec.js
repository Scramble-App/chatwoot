import { mount, flushPromises } from '@vue/test-utils';
import InboxDisplayMenu from '../InboxDisplayMenu.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

vi.mock('dashboard/composables/useUISettings');

const updateUISettings = vi.fn();

// The saved options are applied once the menu has mounted
const mountMenu = async uiSettings => {
  useUISettings.mockReturnValue({ uiSettings, updateUISettings });
  const wrapper = mount(InboxDisplayMenu, {
    global: { directives: { onClickaway: {} } },
  });
  await flushPromises();
  return wrapper;
};

const checkbox = (wrapper, key) => wrapper.find(`input#${key}`).element;

describe('InboxDisplayMenu.vue', () => {
  it('checks snoozed and read by default', async () => {
    const wrapper = await mountMenu({});

    expect(checkbox(wrapper, 'snoozed').checked).toBe(true);
    expect(checkbox(wrapper, 'read').checked).toBe(true);
  });

  it('keeps the options the agent turned off', async () => {
    const wrapper = await mountMenu({
      inbox_filter_by: { status: '', type: '', sort_by: 'desc' },
    });

    expect(checkbox(wrapper, 'snoozed').checked).toBe(false);
    expect(checkbox(wrapper, 'read').checked).toBe(false);
  });

  it('saves turning snoozed off while keeping read', async () => {
    const wrapper = await mountMenu({});

    await wrapper.find('input#snoozed').trigger('change');

    expect(updateUISettings).toHaveBeenCalledWith({
      inbox_filter_by: { status: '', type: 'read', sort_by: 'desc' },
    });
  });
});
