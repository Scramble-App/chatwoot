import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import CustomerIdentitySuggestionBanner from '../CustomerIdentitySuggestionBanner.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) => {
      if (key === 'CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.MESSAGE') {
        return `Found a customer by email: ${params.customer}`;
      }
      return key;
    },
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const buttonStub = {
  props: ['label', 'disabled', 'isLoading'],
  emits: ['click'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};

describe('CustomerIdentitySuggestionBanner', () => {
  const pendingChat = {
    id: 42,
    additional_attributes: {
      customer_identity_suggestion: {
        status: 'pending',
        email: 'customer@example.com',
        matched_contact_name: 'Customer Name',
      },
    },
  };

  const createWrapper = ({
    chat = pendingChat,
    dispatch = vi.fn(() => Promise.resolve()),
  } = {}) => {
    const store = createStore({});
    store.dispatch = dispatch;

    return mount(CustomerIdentitySuggestionBanner, {
      props: { chat },
      global: {
        plugins: [store],
        stubs: {
          Button: buttonStub,
        },
      },
    });
  };

  it('renders a pending suggestion with customer name and email', () => {
    const wrapper = createWrapper();

    expect(wrapper.text()).toContain(
      'Found a customer by email: Customer Name (customer@example.com)'
    );
    expect(wrapper.text()).toContain('Link');
    expect(wrapper.text()).toContain('Dismiss');
  });

  it('does not render dismissed or linked suggestions', () => {
    const dismissedWrapper = createWrapper({
      chat: {
        id: 42,
        additional_attributes: {
          customer_identity_suggestion: {
            status: 'dismissed',
            email: 'customer@example.com',
          },
        },
      },
    });
    const linkedWrapper = createWrapper({
      chat: {
        id: 42,
        additional_attributes: {
          customer_identity_suggestion: {
            status: 'linked',
            email: 'customer@example.com',
          },
        },
      },
    });

    expect(dismissedWrapper.text()).toBe('');
    expect(linkedWrapper.text()).toBe('');
  });

  it('dispatches link and dismiss actions', async () => {
    const dispatch = vi.fn(() => Promise.resolve());
    const wrapper = createWrapper({ dispatch });
    const buttons = wrapper.findAll('button');

    await buttons[0].trigger('click');
    await buttons[1].trigger('click');

    expect(dispatch).toHaveBeenCalledWith('linkCustomerIdentitySuggestion', {
      conversationId: 42,
    });
    expect(dispatch).toHaveBeenCalledWith('dismissCustomerIdentitySuggestion', {
      conversationId: 42,
    });
  });
});
