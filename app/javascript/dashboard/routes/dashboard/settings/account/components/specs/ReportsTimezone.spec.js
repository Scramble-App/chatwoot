import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ReportsTimezone from '../ReportsTimezone.vue';
import { useAccount } from 'dashboard/composables/useAccount';

vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const updateAccount = vi.fn();

const mountComponent = settings => {
  useAccount.mockReturnValue({
    currentAccount: ref({ id: 1, settings }),
    updateAccount,
  });
  return mount(ReportsTimezone);
};

describe('ReportsTimezone.vue', () => {
  beforeEach(() => {
    updateAccount.mockResolvedValue({});
  });

  it('selects the saved reports timezone', () => {
    const wrapper = mountComponent({ reporting_timezone: 'Europe/Tallinn' });

    expect(wrapper.find('select').element.value).toBe('Europe/Tallinn');
  });

  it('follows the browser timezone when none is saved', () => {
    const wrapper = mountComponent({});

    expect(wrapper.find('select').element.value).toBe('');
  });

  it('saves the picked timezone', async () => {
    const wrapper = mountComponent({});

    await wrapper.find('select').setValue('Europe/Tallinn');
    await flushPromises();

    expect(updateAccount).toHaveBeenCalledWith(
      { reporting_timezone: 'Europe/Tallinn' },
      { silent: true }
    );
  });

  it('clears the timezone to follow the browser again', async () => {
    const wrapper = mountComponent({ reporting_timezone: 'Europe/Tallinn' });

    await wrapper.find('select').setValue('');
    await flushPromises();

    expect(updateAccount).toHaveBeenCalledWith(
      { reporting_timezone: null },
      { silent: true }
    );
  });
});
