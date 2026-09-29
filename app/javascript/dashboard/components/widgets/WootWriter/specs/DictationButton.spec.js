import { mount, flushPromises } from '@vue/test-utils';
import DictationButton from '../DictationButton.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { transcribeDictation: vi.fn() },
}));

class FakeMediaRecorder {
  static isTypeSupported = type => type === 'audio/webm;codecs=opus';

  constructor(stream, options) {
    this.stream = stream;
    this.mimeType = options.mimeType;
  }

  start() {
    this.state = 'recording';
  }

  stop() {
    this.ondataavailable({
      data: new Blob(['voice'], { type: this.mimeType }),
    });
    this.onstop();
  }
}

const track = { stop: vi.fn() };
const getUserMedia = vi.fn();

const mountButton = () =>
  mount(DictationButton, { props: { conversationId: 7 } });

describe('DictationButton', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getUserMedia.mockResolvedValue({ getTracks: () => [track] });
    Object.defineProperty(navigator, 'mediaDevices', {
      value: { getUserMedia },
      configurable: true,
    });
    vi.stubGlobal('MediaRecorder', FakeMediaRecorder);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('records a reply, transcribes it and inserts the text into the editor', async () => {
    ConversationApi.transcribeDictation.mockResolvedValue({
      data: { text: 'Hello there' },
    });
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = mountButton();

    await wrapper.find('button').trigger('click');
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(getUserMedia).toHaveBeenCalledWith({ audio: true });
    expect(ConversationApi.transcribeDictation).toHaveBeenCalledWith({
      conversationId: 7,
      audio: expect.any(Blob),
      fileName: 'dictation.webm',
    });
    expect(emit).toHaveBeenCalledWith(
      BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
      'Hello there'
    );
    expect(track.stop).toHaveBeenCalled();
  });

  it('explains when the microphone is not available', async () => {
    getUserMedia.mockRejectedValue(new Error('NotAllowedError'));
    const wrapper = mountButton();

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.REPLYBOX.DICTATION.MICROPHONE_ERROR'
    );
    expect(ConversationApi.transcribeDictation).not.toHaveBeenCalled();
  });

  it('shows the error from the server when the transcription fails', async () => {
    ConversationApi.transcribeDictation.mockRejectedValue({
      response: { data: { error: 'OpenAI integration is not configured' } },
    });
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = mountButton();

    await wrapper.find('button').trigger('click');
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'OpenAI integration is not configured'
    );
    expect(emit).not.toHaveBeenCalledWith(
      BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
      expect.anything()
    );
  });

  it('drops the recording when the agent switches to another conversation', async () => {
    const wrapper = mountButton();

    await wrapper.find('button').trigger('click');
    await flushPromises();
    await wrapper.setProps({ conversationId: 8 });
    await flushPromises();

    expect(track.stop).toHaveBeenCalled();
    expect(ConversationApi.transcribeDictation).not.toHaveBeenCalled();
  });
});
