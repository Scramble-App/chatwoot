import { mount } from '@vue/test-utils';
import CopilotReplyBottomPanel from '../CopilotReplyBottomPanel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

// NextButton is stubbed globally, so its label prop is rendered as an attribute
const buttonLabelled = (wrapper, label) =>
  wrapper
    .findAll('button')
    .find(button => button.attributes('label').startsWith(label));

describe('CopilotReplyBottomPanel', () => {
  it('lets the agent discard a generation that is still running', async () => {
    const wrapper = mount(CopilotReplyBottomPanel, {
      props: { isGeneratingContent: true },
    });
    const discard = buttonLabelled(wrapper, 'GENERAL.DISCARD');

    expect(discard.attributes('disabled')).toBeUndefined();
    expect(
      buttonLabelled(wrapper, 'GENERAL.ACCEPT').attributes('disabled')
    ).toBeDefined();
    expect(
      buttonLabelled(wrapper, 'CONVERSATION.CONTEXT_MENU.COPY').attributes(
        'disabled'
      )
    ).toBeDefined();

    await discard.trigger('click');

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });
});
