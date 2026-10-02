import { shallowMount, flushPromises } from '@vue/test-utils';
import { formatInTimeZone } from 'date-fns-tz';
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

  describe('special schedule', () => {
    const specialDays = [
      { date: '2026-10-05', day_off: true },
      {
        date: '2026-10-06',
        day_off: false,
        open_hour: 10,
        open_minutes: 0,
        close_hour: 18,
        close_minutes: 30,
      },
    ];

    it('submits each date with its hours or as a day off', async () => {
      const wrapper = mountComponent({ specialDays });

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(dispatch).toHaveBeenCalledWith(
        'agents/update',
        expect.objectContaining({
          special_days: [
            { date: '2026-10-05', day_off: true },
            {
              date: '2026-10-06',
              day_off: false,
              open_hour: 10,
              open_minutes: 0,
              close_hour: 18,
              close_minutes: 30,
            },
          ],
        })
      );
    });

    it('hides the hours of a day off', () => {
      const wrapper = mountComponent({ specialDays });
      const [dayOff, workingDay] = wrapper.findAll(
        '[data-test-id="agent-special-day"]'
      );

      expect(dayOff.findAll('input[type="time"]')).toHaveLength(0);
      expect(workingDay.findAll('input[type="time"]')).toHaveLength(2);
    });

    it('adds a day that cannot be before today in the schedule timezone', async () => {
      const wrapper = mountComponent({ scheduleTimezone: 'Europe/Tallinn' });

      await wrapper
        .find('[data-test-id="agent-special-day-add"]')
        .trigger('click');

      const dateInput = wrapper.find(
        '[data-test-id="agent-special-day"] input[type="date"]'
      );
      const today = formatInTimeZone(
        new Date(),
        'Europe/Tallinn',
        'yyyy-MM-dd'
      );
      expect(dateInput.element.value).toBe(today);
      expect(dateInput.attributes('min')).toBe(today);
    });
  });
});
