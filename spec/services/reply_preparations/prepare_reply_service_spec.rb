require 'rails_helper'

RSpec.describe ReplyPreparations::PrepareReplyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:openai_service) { instance_double(ReplyPreparations::OpenaiPrepareReplyService, perform: 'Hazırlanmış yanıt') }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  it 'uses recent incoming customer messages as language context' do
    create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation, content: 'Outgoing agent message')
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Older Turkish text', created_at: 2.minutes.ago)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      content: 'Merhaba, hesabıma giriş yapamıyorum.',
      created_at: 1.minute.ago
    )
    create(
      :integrations_hook,
      :openai,
      account: account,
      settings: { 'api_key' => 'sk-test', 'translation_model' => 'gpt-test' }
    )

    allow(ReplyPreparations::OpenaiPrepareReplyService).to receive(:new).and_return(openai_service)

    result = described_class.new(conversation: conversation, content: 'Please try again.').perform

    expect(result).to eq('Hazırlanmış yanıt')
    expect(ReplyPreparations::OpenaiPrepareReplyService).to have_received(:new).with(
      hook: instance_of(Integrations::Hook),
      content: 'Please try again.',
      customer_context: "Older Turkish text\n\n---\n\nMerhaba, hesabıma giriş yapamıyorum."
    )
  end

  it 'raises a controlled error when the draft is blank' do
    expect { described_class.new(conversation: conversation, content: ' ').perform }
      .to raise_error(described_class::Error, 'Reply content is required')
  end

  it 'raises a controlled error when OpenAI integration is not configured' do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Hola')

    expect { described_class.new(conversation: conversation, content: 'Hello').perform }
      .to raise_error(described_class::Error, 'OpenAI integration is not configured')
  end

  it 'raises a controlled error when there is no incoming customer context' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })

    expect { described_class.new(conversation: conversation, content: 'Hello').perform }
      .to raise_error(described_class::Error, 'No incoming customer messages available for language detection')
  end
end
