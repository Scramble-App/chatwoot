require 'rails_helper'

RSpec.describe ConversationSummaries::SummaryService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:openai_service) { instance_double(ConversationSummaries::OpenaiSummaryService, perform: 'Conversation summary') }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  it 'uses customer messages, public agent replies, and internal private notes as summary context' do
    account.account_users.find_by(user: user).update!(translation_locale: 'ru')
    create_customer_message('Customer needs invoice help', created_at: 2.minutes.ago)
    create_agent_message('Operator promised to resend invoice', created_at: 1.minute.ago)
    create_agent_message('Invoice was sent by email', created_at: 30.seconds.ago, private_message: true)
    create_customer_message('Private incoming note', created_at: Time.zone.now, private_message: true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test', 'translation_model' => 'gpt-test' })

    allow(ConversationSummaries::OpenaiSummaryService).to receive(:new).and_return(openai_service)

    result = described_class.new(conversation: conversation, user: user).perform

    expect(result).to eq('Conversation summary')
    expect(ConversationSummaries::OpenaiSummaryService).to have_received(:new).with(
      hook: instance_of(Integrations::Hook),
      conversation_context: [
        'Customer: Customer needs invoice help',
        'Agent reply to customer: Operator promised to resend invoice',
        'Internal private note: Invoice was sent by email'
      ].join("\n"),
      output_language: 'Russian (ru)'
    )
  end

  it 'uses the latest 10 customer messages as the summary window and includes later agent activity' do
    start_time = 1.hour.ago

    create_customer_message('Customer question 1', created_at: start_time)
    create_agent_message('Old reply outside summary window', created_at: start_time + 30.seconds)

    (2..11).each do |index|
      create_customer_message("Customer question #{index}", created_at: start_time + index.minutes)
    end

    create_agent_message('Latest public reply', created_at: start_time + 12.minutes)
    create_agent_message('Latest internal action', created_at: start_time + 13.minutes, private_message: true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })

    allow(ConversationSummaries::OpenaiSummaryService).to receive(:new).and_return(openai_service)

    described_class.new(conversation: conversation, user: user).perform

    expect(ConversationSummaries::OpenaiSummaryService).to have_received(:new) do |args|
      context = args[:conversation_context]
      context_lines = context.lines.map(&:chomp)

      expect(context_lines).not_to include('Customer: Customer question 1')
      expect(context).not_to include('Old reply outside summary window')
      expect(context).to include('Customer: Customer question 2')
      expect(context).to include('Customer: Customer question 11')
      expect(context).to include('Agent reply to customer: Latest public reply')
      expect(context).to include('Internal private note: Latest internal action')
    end
  end

  it 'falls back to the account locale when the operator language is blank' do
    account.update!(locale: 'fr')
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Bonjour')
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })

    allow(ConversationSummaries::OpenaiSummaryService).to receive(:new).and_return(openai_service)

    described_class.new(conversation: conversation, user: user).perform

    expect(ConversationSummaries::OpenaiSummaryService).to have_received(:new).with(
      hook: instance_of(Integrations::Hook),
      conversation_context: 'Customer: Bonjour',
      output_language: 'French (fr)'
    )
  end

  it 'raises a controlled error when OpenAI integration is not configured' do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Hola')

    expect { described_class.new(conversation: conversation, user: user).perform }
      .to raise_error(described_class::Error, 'OpenAI integration is not configured')
  end

  it 'raises a controlled error when there is no conversation context' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })

    expect { described_class.new(conversation: conversation, user: user).perform }
      .to raise_error(described_class::Error, 'No conversation messages available to summarize')
  end

  def create_customer_message(content, created_at:, private_message: false)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      content: content,
      private: private_message,
      created_at: created_at
    )
  end

  def create_agent_message(content, created_at:, private_message: false)
    create(
      :message,
      :bot_message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      content: content,
      private: private_message,
      created_at: created_at
    )
  end
end
