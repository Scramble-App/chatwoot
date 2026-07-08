require 'rails_helper'

RSpec.describe ReplyPreparations::OpenaiPrepareReplyService do
  let(:hook) do
    build(
      :integrations_hook,
      :openai,
      settings: {
        'api_key' => 'sk-test',
        'translation_model' => 'gpt-5.1',
        'translation_reasoning_effort' => 'high',
        'translation_max_output_tokens' => 900,
        'translation_temperature' => 0.1,
        'reply_tone_instructions' => 'Warm, concise, and confident.',
        'prepare_answer_instructions' => 'Custom prepare answer instructions.'
      }
    )
  end

  it 'prepares replies through the OpenAI Responses API using configured settings' do
    request = stub_request(:post, 'https://api.openai.com/v1/responses')
              .with do |req|
                body = JSON.parse(req.body)
                req.headers['Authorization'] == 'Bearer sk-test' &&
                  body['model'] == 'gpt-5.1' &&
                  body['reasoning'] == { 'effort' => 'high' } &&
                  body['max_output_tokens'] == 900 &&
                  !body.key?('temperature') &&
                  body['store'] == false &&
                  body['instructions'].include?('Custom prepare answer instructions.') &&
                  body['input'].include?('Warm, concise, and confident.') &&
                  body['input'].include?('Merhaba, hesabıma giriş yapamıyorum.') &&
                  body['input'].include?('Please try signing in again.')
              end
              .to_return(
                status: 200,
                body: { output_text: 'Lütfen tekrar giriş yapmayı deneyin.' }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    result = described_class.new(
      hook: hook,
      content: 'Please try signing in again.',
      customer_context: 'Merhaba, hesabıma giriş yapamıyorum.'
    ).perform

    expect(result).to eq('Lütfen tekrar giriş yapmayı deneyin.')
    expect(request).to have_been_requested
  end
end
