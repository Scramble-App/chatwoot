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
        'source_types' => 'confluence, jira',
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
      source_types: %w[confluence jira],
      limit: 3
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
