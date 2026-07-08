require 'rails_helper'

RSpec.describe ConversationSummaries::OpenaiSummaryService do
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
        'summary_instructions' => 'Custom summary instructions. Mention internal actions accurately.'
      }
    )
  end

  it 'summarizes conversations through the OpenAI Responses API using configured settings' do
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
                  body['instructions'].include?('Ignore the customer language for the summary language') &&
                  body['instructions'].include?('Custom summary instructions. Mention internal actions accurately.') &&
                  body['input'].include?('Warm, concise, and confident.') &&
                  body['input'].include?('Customer: Добрий день, я не бачу рахунок у кабінеті') &&
                  body['input'].include?('Internal private note: Рахунок надіслано вам на електронну пошту') &&
                  body['instructions'].include?('Return only text in the output language')
              end
              .to_return(
                status: 200,
                body: { output_text: 'Клиент не может найти счет.' }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    result = described_class.new(
      hook: hook,
      conversation_context: [
        'Customer: Добрий день, я не бачу рахунок у кабінеті',
        'Internal private note: Рахунок надіслано вам на електронну пошту'
      ].join("\n"),
      output_language: 'Russian (ru)'
    ).perform

    expect(result).to eq('Клиент не может найти счет.')
    expect(request).to have_been_requested
  end
end
