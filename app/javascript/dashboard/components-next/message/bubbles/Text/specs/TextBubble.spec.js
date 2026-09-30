import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import TextBubble from '../Index.vue';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_TYPES } from '../../../constants';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
}));
vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: ref(false),
    translationContent: ref(null),
  }),
}));

const mountBubble = messageType => {
  const Parent = defineComponent({
    setup() {
      provideMessageContext({
        content: ref('Γεια σας! Μπορείτε να κάνετε ανάληψη.'),
        attachments: ref([]),
        contentAttributes: ref({}),
        messageType: ref(messageType),
        operatorTranslation: ref({
          content: 'Здравствуйте! Вы можете вывести деньги.',
        }),
      });
      return () => h(TextBubble);
    },
  });

  return mount(Parent, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        FormattedContent: {
          props: ['content'],
          template: '<p>{{ content }}</p>',
        },
        AttachmentChips: true,
        TranslationToggle: true,
      },
    },
  });
};

describe('TextBubble operator translation', () => {
  it('shows the translation under a customer message', () => {
    expect(mountBubble(MESSAGE_TYPES.INCOMING).text()).toContain(
      'Вы можете вывести деньги'
    );
  });

  it('shows the translation under an agent reply, so other operators can read it', () => {
    const text = mountBubble(MESSAGE_TYPES.OUTGOING).text();

    expect(text).toContain('Μπορείτε να κάνετε ανάληψη');
    expect(text).toContain('Вы можете вывести деньги');
  });

  it('does not show it for other message types', () => {
    expect(mountBubble(MESSAGE_TYPES.TEMPLATE).text()).not.toContain(
      'Вы можете вывести деньги'
    );
  });
});
