require 'rails_helper'

RSpec.describe MessageTranslations::TranslateMessageService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Hola') }
  let(:openai_service) { instance_double(MessageTranslations::OpenaiTranslationService, perform: 'Hello') }
  let(:hook) do
    create(
      :integrations_hook,
      :openai,
      account: account,
      settings: {
        'api_key' => 'sk-test',
        'translation_enabled' => true,
        'translation_model' => 'gpt-test'
      }
    )
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    admin.account_users.find_by(account: account).update!(translation_locale: 'en')
    allow(MessageTranslations::OpenaiTranslationService).to receive(:new).and_return(openai_service)
    allow(ActionCableBroadcastJob).to receive(:perform_later)
    hook
  end

  it 'stores operator translations separately from message content attributes' do
    translation = described_class.new(message: message, target_locale: 'en').perform

    expect(translation).to be_completed
    expect(translation.content).to eq('Hello')
    expect(translation.model).to eq('gpt-test')
    expect(message.reload.content_attributes['translations']).to be_blank
  end

  it 'broadcasts the translation only to operators configured for that locale' do
    translation = described_class.new(message: message, target_locale: 'en').perform

    expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
      [admin.pubsub_token],
      'message.translation_updated',
      {
        account_id: account.id,
        conversation_id: conversation.display_id,
        message_id: message.id,
        operator_translation: translation.push_event_data
      }
    )
  end

  it 'does not translate outgoing messages' do
    outgoing_message = create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation, content: 'Hola')

    expect(described_class.new(message: outgoing_message, target_locale: 'en').perform).to be_nil
    expect(MessageTranslation.where(message: outgoing_message)).to be_blank
  end

  it 'retries a failed existing translation instead of creating a duplicate' do
    translation = MessageTranslation.create!(
      account: account,
      message: message,
      target_locale: 'en',
      provider: MessageTranslation::PROVIDER_OPENAI,
      status: :failed,
      error_message: 'Previous OpenAI error'
    )

    result = described_class.new(message: message, target_locale: 'en').perform

    expect(result.id).to eq(translation.id)
    expect(result).to be_completed
    expect(result.content).to eq('Hello')
    expect(result.error_message).to be_nil
    expect(MessageTranslation.where(message: message, target_locale: 'en').count).to eq(1)
  end
end
