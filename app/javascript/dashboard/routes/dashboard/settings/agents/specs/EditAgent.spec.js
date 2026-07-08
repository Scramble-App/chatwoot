import { shallowMount, flushPromises } from '@vue/test-utils';
import EditAgent from '../EditAgent.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useConfig } from 'dashboard/composables/useConfig';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useConfig');
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const dispatch = vi.fn();

const mountComponent = props =>
  shallowMount(EditAgent, {
    props: {
      id: 1,
      name: 'Ben Nugent',
      email: 'ben@example.com',
      type: 'agent',
      availability: 'offline',
      scheduleEnabled: true,
      scheduleTimezone: '',
      workingHours: [],
      scheduleExceptions: [],
      ...props,
    },
    global: {
      mocks: {
        $t: key => key,
      },
      stubs: {
        Button: {
          template: '<button v-bind="$attrs"><slot />{{ label }}</button>',
          props: ['label'],
        },
        'woot-modal-header': true,
      },
    },
  });

describe('EditAgent.vue', () => {
  beforeEach(() => {
    dispatch.mockResolvedValue({});
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(getter => {
      if (getter === 'customRole/getCustomRoles') {
        return { value: [] };
      }

      return { value: { isUpdating: false } };
    });
    useConfig.mockReturnValue({ enabledLanguages: [] });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('selects Europe/Tallinn when the agent has no schedule timezone', () => {
    const wrapper = mountComponent();
    const timezoneSelect = wrapper.find(
      '[data-test-id="agent-schedule-timezone-select"]'
    );

    expect(timezoneSelect.element.value).toBe('Europe/Tallinn');
  });

  it('keeps an existing UTC schedule timezone selected', () => {
    const wrapper = mountComponent({ scheduleTimezone: 'UTC' });
    const timezoneSelect = wrapper.find(
      '[data-test-id="agent-schedule-timezone-select"]'
    );

    expect(timezoneSelect.element.value).toBe('UTC');
  });

  it('submits Europe/Tallinn as the default schedule timezone', async () => {
    const wrapper = mountComponent();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'agents/update',
      expect.objectContaining({
        id: 1,
        schedule_enabled: true,
        schedule_timezone: 'Europe/Tallinn',
      })
    );
  });
});
