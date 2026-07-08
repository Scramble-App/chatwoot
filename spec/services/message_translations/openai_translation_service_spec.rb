require 'rails_helper'

RSpec.describe MessageTranslations::OpenaiTranslationService do
  let(:account) { create(:account) }
  let(:message) { create(:message, account: account, content: 'Hola, necesito ayuda') }
  let(:hook) do
    build(
      :integrations_hook,
      :openai,
      settings: {
        'api_key' => 'sk-test',
        'translation_model' => 'gpt-5.1',
        'translation_reasoning_effort' => 'high',
        'translation_max_output_tokens' => 800,
        'translation_temperature' => 0.1,
        'translation_instructions' => 'Custom translation instructions.'
      }
    )
  end

  it 'translates content through the OpenAI Responses API using configured settings' do
    request = stub_request(:post, 'https://api.openai.com/v1/responses')
              .with do |req|
                body = JSON.parse(req.body)
                req.headers['Authorization'] == 'Bearer sk-test' &&
                  body['model'] == 'gpt-5.1' &&
                  body['reasoning'] == { 'effort' => 'high' } &&
                  body['max_output_tokens'] == 800 &&
                  !body.key?('temperature') &&
                  body['store'] == false &&
                  body['instructions'].include?('Custom translation instructions.') &&
                  body['input'].include?('Target language locale: en') &&
                  body['input'].include?('Hola, necesito ayuda')
              end
              .to_return(
                status: 200,
                body: { output_text: 'Hello, I need help' }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    result = described_class.new(hook: hook, message: message, target_locale: 'en').perform

    expect(result).to eq('Hello, I need help')
    expect(request).to have_been_requested
  end
end
