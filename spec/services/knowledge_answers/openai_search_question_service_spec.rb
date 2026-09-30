require 'rails_helper'

RSpec.describe KnowledgeAnswers::OpenaiSearchQuestionService do
  let(:effort) { 'high' }
  let(:openai_hook) do
    build(:integrations_hook, :openai,
          settings: { 'api_key' => 'sk-test', 'translation_model' => 'gpt-5.1', 'translation_reasoning_effort' => effort })
  end
  let(:onyx_settings) { {} }
  let(:onyx_hook) do
    build(:integrations_hook, :onyx_mcp, settings: { 'mcp_url' => 'https://cloud.onyx.app/mcp', 'api_token' => 'onyx-token' }.merge(onyx_settings))
  end
  let(:conversation_context) do
    [
      'Customer: Como verifico a minha conta?',
      'Agent reply to customer: Envie uma foto do documento na app.',
      'Customer: Obrigado, já está. Fiz uma transferência de 50€ para a minha conta',
      'Customer: Quando chega o dinheiro?'
    ].join("\n")
  end
  let(:sent_bodies) { [] }

  def reply_with(text)
    body = { status: 'completed', output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: text }] }] }
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      sent_bodies << JSON.parse(request.body)
      { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def search_question
    described_class.new(openai_hook: openai_hook, onyx_hook: onyx_hook, conversation_context: conversation_context).perform
  end

  # Rejected params are remembered in Redis, which is not reset between examples
  before do
    %w[low none].each do |value|
      Redis::Alfred.delete(format(Redis::Alfred::OPENAI_UNSUPPORTED_PARAMS, model: 'gpt-5.1', reasoning_effort: value))
    end
  end

  it 'asks OpenAI for one self-contained question about the conversation' do
    reply_with("  When does a bank transfer to a Scramble account arrive?\n")

    expect(search_question).to eq('When does a bank transfer to a Scramble account arrive?')

    body = sent_bodies.first
    expect(body['model']).to eq('gpt-5.1')
    # Agent replies are sent too, so the model can tell which questions are already resolved
    expect(body['input']).to include('Agent reply to customer: Envie uma foto', 'Fiz uma transferência de 50€',
                                     'Quando chega o dinheiro?')
    expect(body['instructions']).to include('latest questions that are still unresolved', 'Ignore questions that an agent already answered',
                                            'in English', 'Leave out personal data')
    expect(body['store']).to be(false)
  end

  it 'uses a low reasoning effort, so a high configured effort does not delay the search' do
    reply_with('When does a bank transfer arrive?')

    search_question

    expect(sent_bodies.first['reasoning']).to eq('effort' => 'low')
  end

  context 'with a configured effort that is already faster' do
    let(:effort) { 'none' }

    it 'keeps it' do
      reply_with('When does a bank transfer arrive?')

      search_question

      expect(sent_bodies.first['reasoning']).to eq('effort' => 'none')
    end
  end

  context 'with search question instructions' do
    let(:onyx_settings) { { 'query_template' => 'Use the product names Group A and Group B.' } }

    it 'adds them to the instructions' do
      reply_with('What is the difference between Group A and Group B?')

      search_question

      expect(sent_bodies.first['instructions']).to end_with('Use the product names Group A and Group B.')
    end
  end

  context 'with a query template saved before the question was generated' do
    let(:onyx_settings) { { 'query_template' => 'Support question: {{conversation_context}}' } }

    it 'does not pass the old template to OpenAI' do
      reply_with('When does a bank transfer arrive?')

      search_question

      expect(sent_bodies.first['instructions']).not_to include('{{conversation_context}}')
    end
  end

  it 'raises when OpenAI returns no question' do
    reply_with('   ')

    expect { search_question }.to(raise_error do |error|
      expect(error.class.name).to eq('KnowledgeAnswers::OpenaiSearchQuestionService::Error')
      expect(error.message).to eq('OpenAI returned an empty knowledge base search question')
    end)
  end
end
