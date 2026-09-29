import ReplyBottomPanel from '../ReplyBottomPanel.vue';

const { isDictationAvailable, showAudioRecorderButton } =
  ReplyBottomPanel.computed;

const panel = ({ appIntegrations }) => {
  const context = {
    appIntegrations,
    isEditorDisabled: false,
    isALineChannel: false,
    isATiktokChannel: false,
    showAudioRecorder: true,
    accountId: 1,
    isFeatureEnabledonAccount: () => true,
  };
  context.isDictationAvailable = isDictationAvailable.call(context);
  return context;
};

describe('ReplyBottomPanel microphone', () => {
  it('dictates instead of recording a voice message when OpenAI is set up', () => {
    const context = panel({
      appIntegrations: [{ id: 'openai', hooks: [{ id: 1 }] }],
    });

    expect(context.isDictationAvailable).toBe(true);
    expect(showAudioRecorderButton.call(context)).toBe(false);
  });

  it('keeps the voice message recorder without an OpenAI hook', () => {
    const context = panel({ appIntegrations: [{ id: 'openai', hooks: [] }] });

    expect(context.isDictationAvailable).toBe(false);
    expect(showAudioRecorderButton.call(context)).toBe(true);
  });
});
