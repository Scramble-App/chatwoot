require 'rails_helper'

RSpec.describe KnowledgeAnswers::OpenaiAnswerService do
  let(:openai_hook) do
    build(
      :integrations_hook,
      :openai,
      settings: {
        'api_key' => 'sk-test',
        'translation_model' => 'gpt-5.1',
        'translation_reasoning_effort' => 'high',
        'translation_max_output_tokens' => 900,
        'translation_temperature' => 0.1
      }
    )
  end
  let(:onyx_hook) do
    build(
      :integrations_hook,
      :onyx_mcp,
      settings: {
        'mcp_url' => 'https://cloud.onyx.app/mcp',
        'api_token' => 'onyx-token',
        'answer_guardrails' => 'Use only approved knowledge base facts.',
        'reply_tone_instructions' => 'Plain, direct, and helpful.'
      }
    )
  end

  it 'drafts a knowledge answer through OpenAI using Onyx guardrails and operator language' do
    request = stub_request(:post, 'https://api.openai.com/v1/responses')
              .with do |req|
                body = JSON.parse(req.body)
                req.headers['Authorization'] == 'Bearer sk-test' &&
                  body['model'] == 'gpt-5.1' &&
                  body['reasoning'] == { 'effort' => 'high' } &&
                  body['max_output_tokens'] == 900 &&
                  !body.key?('temperature') &&
                  body['store'] == false &&
                  body['instructions'].include?('Output language must be Russian (ru)') &&
                  body['instructions'].include?('Use only approved knowledge base facts.') &&
                  body['input'].include?('Plain, direct, and helpful.') &&
                  body['input'].include?('Customer: Где счет?') &&
                  body['input'].include?('Knowledge result 1:')
              end
              .to_return(
                status: 200,
                body: { output_text: 'Счет доступен в разделе биллинга.' }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    result = described_class.new(
      openai_hook: openai_hook,
      onyx_hook: onyx_hook,
      conversation_context: 'Customer: Где счет?',
      knowledge_context: 'Knowledge result 1: Billing guide',
      output_language: 'Russian (ru)'
    ).perform

    expect(result).to eq('Счет доступен в разделе биллинга.')
    expect(request).to have_been_requested
  end
end
