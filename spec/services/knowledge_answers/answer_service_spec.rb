require 'rails_helper'

RSpec.describe KnowledgeAnswers::AnswerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:onyx_client) { instance_double(Integrations::OnyxMcp::Client) }
  let(:openai_service) { instance_double(KnowledgeAnswers::OpenaiAnswerService, perform: 'Knowledge answer draft') }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    account.account_users.find_by(user: user).update!(translation_locale: 'ru')
  end

  it 'uses public conversation context, Onyx indexed documents, and OpenAI output language' do
    create_customer_message('How can I find my invoice?', created_at: 2.minutes.ago)
    create_agent_message('Please check your billing page.', created_at: 1.minute.ago)
    create_agent_message('Internal billing check', created_at: 30.seconds.ago, private_message: true)
    openai_hook = create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
    onyx_hook = create(
      :integrations_hook,
      :onyx_mcp,
      account: account,
      settings: {
        'mcp_url' => 'https://cloud.onyx.app/mcp',
        'api_token' => 'onyx-token',
        'source_types' => 'Confluence, jira',
        'result_limit' => 3,
        'query_template' => 'Support question: {{conversation_context}}'
      }
    )

    allow(Integrations::OnyxMcp::Client).to receive(:new).with(hook: onyx_hook).and_return(onyx_client)
    allow(onyx_client).to receive(:search_indexed_documents).and_return(
      'documents' => [
        {
          'semantic_identifier' => 'Billing guide',
          'source_type' => 'confluence',
          'link' => 'https://docs.example.test/billing',
          'content' => 'Invoices are available in Billing > Documents.'
        }
      ]
    )
    allow(KnowledgeAnswers::OpenaiAnswerService).to receive(:new).and_return(openai_service)

    result = described_class.new(conversation: conversation, user: user).perform

    expect(result).to eq('Knowledge answer draft')
    expect(onyx_client).to have_received(:search_indexed_documents).with(
      query: include('Customer: How can I find my invoice?', 'Agent reply to customer: Please check your billing page.'),
      source_types: %w[confluence jira]
    )
    expect(KnowledgeAnswers::OpenaiAnswerService).to have_received(:new).with(
      openai_hook: openai_hook,
      onyx_hook: onyx_hook,
      conversation_context: [
        'Customer: How can I find my invoice?',
        'Agent reply to customer: Please check your billing page.'
      ].join("\n"),
      knowledge_context: include('Billing guide', 'Invoices are available in Billing > Documents.'),
      output_language: 'Russian (ru)'
    )
  end

  it 'raises a controlled error when Onyx integration is not configured' do
    create_customer_message('How do I cancel?', created_at: Time.zone.now)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })

    expect { described_class.new(conversation: conversation, user: user).perform }
      .to raise_error(described_class::Error, 'Onyx MCP integration is not configured')
  end

  it 'raises a controlled error when Onyx returns no documents' do
    create_customer_message('How do I cancel?', created_at: Time.zone.now)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
    onyx_hook = create(:integrations_hook, :onyx_mcp, account: account)

    allow(Integrations::OnyxMcp::Client).to receive(:new).with(hook: onyx_hook).and_return(onyx_client)
    allow(onyx_client).to receive(:search_indexed_documents).and_return('documents' => [])

    expect { described_class.new(conversation: conversation, user: user).perform }
      .to raise_error(described_class::Error, 'No knowledge base results found in Onyx')
  end

  it 'uses Onyx results payloads and limits documents before sending them to OpenAI' do
    create_customer_message('Where can I check my investment?', created_at: Time.zone.now)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
    onyx_hook = create(
      :integrations_hook,
      :onyx_mcp,
      account: account,
      settings: {
        'mcp_url' => 'https://cloud.onyx.app/mcp',
        'api_token' => 'onyx-token',
        'result_limit' => 1
      }
    )

    allow(Integrations::OnyxMcp::Client).to receive(:new).with(hook: onyx_hook).and_return(onyx_client)
    allow(onyx_client).to receive(:search_indexed_documents).and_return(
      'structuredContent' => {
        'results' => [
          {
            'title' => 'Investment guide',
            'source_type' => 'confluence',
            'url' => 'https://docs.example.test/investments',
            'content' => 'Investments are shown on the investment dashboard.'
          },
          {
            'title' => 'Second result',
            'content' => 'This should be excluded by result_limit.'
          }
        ]
      }
    )
    openai_kwargs = nil
    allow(KnowledgeAnswers::OpenaiAnswerService).to receive(:new) do |kwargs|
      openai_kwargs = kwargs
      openai_service
    end

    described_class.new(conversation: conversation, user: user).perform

    expect(openai_kwargs[:knowledge_context]).to include(
      'Investment guide',
      'https://docs.example.test/investments',
      'Investments are shown on the investment dashboard.'
    )
    expect(openai_kwargs[:knowledge_context]).not_to include('Second result')
  end

  describe 'context limits' do
    let(:onyx_hook) { create(:integrations_hook, :onyx_mcp, account: account) }
    let(:openai_kwargs) { {} }

    before do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
      allow(Integrations::OnyxMcp::Client).to receive(:new).with(hook: onyx_hook).and_return(onyx_client)
      allow(KnowledgeAnswers::OpenaiAnswerService).to receive(:new) do |kwargs|
        openai_kwargs.merge!(kwargs)
        openai_service
      end
    end

    it 'keeps the newest messages when the conversation is longer than the limit' do
      stub_const('KnowledgeAnswers::AnswerService::CONVERSATION_CONTEXT_CHARACTER_LIMIT', 60)
      create_customer_message("An old question #{'a' * 30}", created_at: 2.minutes.ago)
      create_customer_message('How do groups A and B differ?', created_at: 1.minute.ago)
      allow(onyx_client).to receive(:search_indexed_documents).and_return('documents' => [{ 'content' => 'Group docs' }])

      described_class.new(conversation: conversation, user: user).perform

      expect(openai_kwargs[:conversation_context]).to eq('Customer: How do groups A and B differ?')
    end

    it 'skips a document that does not fit instead of dropping the rest' do
      stub_const('KnowledgeAnswers::AnswerService::KNOWLEDGE_CONTEXT_CHARACTER_LIMIT', 150)
      create_customer_message('How long do refunds take?', created_at: Time.zone.now)
      allow(onyx_client).to receive(:search_indexed_documents).and_return(
        'documents' => [{ 'content' => 'Refunds take 5 days.' }, { 'content' => 'x' * 500 }, { 'content' => 'Cards arrive in 2 days.' }]
      )

      described_class.new(conversation: conversation, user: user).perform

      expect(openai_kwargs[:knowledge_context]).to include('Refunds take 5 days.', 'Cards arrive in 2 days.')
      expect(openai_kwargs[:knowledge_context]).not_to include('xxx')
    end

    it 'shortens an oversized first document instead of reporting no results' do
      stub_const('KnowledgeAnswers::AnswerService::KNOWLEDGE_CONTEXT_CHARACTER_LIMIT', 150)
      create_customer_message('How long do refunds take?', created_at: Time.zone.now)
      allow(onyx_client).to receive(:search_indexed_documents).and_return('documents' => [{ 'content' => "Refunds take 5 days. #{'x' * 500}" }])

      described_class.new(conversation: conversation, user: user).perform

      expect(openai_kwargs[:knowledge_context]).to start_with("Knowledge result 1:\nContent: Refunds take 5 days.")
      expect(openai_kwargs[:knowledge_context].length).to eq(150)
    end
  end

  describe 'unexpected Onyx result shapes' do
    let(:onyx_hook) { create(:integrations_hook, :onyx_mcp, account: account) }

    before do
      create_customer_message('How long do refunds take?', created_at: Time.zone.now)
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
      allow(Integrations::OnyxMcp::Client).to receive(:new).with(hook: onyx_hook).and_return(onyx_client)
    end

    it 'names the fields of results it cannot read instead of reporting no results' do
      allow(onyx_client).to receive(:search_indexed_documents)
        .and_return('structuredContent' => { 'results' => [{ 'title' => 'Refunds', 'body' => 'Refunds take 5 days.' }] })

      expect { described_class.new(conversation: conversation, user: user).perform }
        .to raise_error(described_class::Error, 'Onyx returned 1 result without readable text (fields: title, body)')
    end

    it 'reports no results for text content that is not a result object' do
      allow(onyx_client).to receive(:search_indexed_documents).and_return('content' => [{ 'type' => 'text', 'text' => '["a", "b"]' }])

      expect { described_class.new(conversation: conversation, user: user).perform }
        .to raise_error(described_class::Error, 'No knowledge base results found in Onyx')
    end

    it 'does not crash when results is an object instead of a list' do
      allow(onyx_client).to receive(:search_indexed_documents).and_return('results' => { 'content' => 'Refunds take 5 days.' })

      expect { described_class.new(conversation: conversation, user: user).perform }
        .to raise_error(described_class::Error, /\AOnyx returned 1 result without readable text/)
    end
  end

  def create_customer_message(content, created_at:)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      content: content,
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
