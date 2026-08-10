import { mount } from '@vue/test-utils';
import CopilotEditorSection from '../CopilotEditorSection.vue';

const stubs = {
  CopilotEditor: { template: '<div class="copilot-editor-stub" />' },
  CaptainLoader: { template: '<span class="captain-loader-stub" />' },
};

const createWrapper = props =>
  mount(CopilotEditorSection, {
    props,
    global: {
      // The real Transition is needed: contentReady rides on its after-enter hook.
      stubs: { ...stubs, transition: false },
      mocks: { $t: key => key },
    },
  });

// Lets the leave/enter transitions run to completion (jsdom reports a zero duration).
const flushTransition = async () => {
  for (let i = 0; i < 4; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, 50);
    });
  }
};

describe('CopilotEditorSection', () => {
  it('emits contentReady when it mounts with a restored generation already shown', async () => {
    const wrapper = createWrapper({
      showCopilotEditor: true,
      isGeneratingContent: false,
      generatedContent: 'restored summary',
    });

    await flushTransition();

    expect(wrapper.emitted('contentReady')).toHaveLength(1);
  });

  it('does not emit contentReady while the generation is still running', async () => {
    const wrapper = createWrapper({
      showCopilotEditor: false,
      isGeneratingContent: true,
      generatedContent: '',
    });

    await flushTransition();

    expect(wrapper.emitted('contentReady')).toBeUndefined();
  });

  it('emits contentReady once when the editor replaces the loading state', async () => {
    const wrapper = createWrapper({
      showCopilotEditor: false,
      isGeneratingContent: true,
      generatedContent: '',
    });

    await flushTransition();
    await wrapper.setProps({
      showCopilotEditor: true,
      isGeneratingContent: false,
      generatedContent: 'fresh summary',
    });
    await flushTransition();

    expect(wrapper.emitted('contentReady')).toHaveLength(1);
  });
});
