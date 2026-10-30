require 'rails_helper'

RSpec.describe DeveloperReports::OpenaiReportService do
  let(:hook) do
    build(:integrations_hook, :openai, settings: {
            'api_key' => 'sk-test', 'translation_model' => 'gpt-5.1', 'translation_max_output_tokens' => 900
          })
  end
  let(:images) { [{ url: 'https://example.com/screenshot.png', data_url: 'data:image/png;base64,iVBORw0KGgo=' }] }
  let(:completed_body) do
    { status: 'completed', output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Отчёт' }] }] }.to_json
  end

  it 'sends the context and each screenshot to the OpenAI Responses API' do
    request = stub_request(:post, 'https://api.openai.com/v1/responses').with do |req|
      body = JSON.parse(req.body)
      req.headers['Authorization'] == 'Bearer sk-test' &&
        body['model'] == 'gpt-5.1' &&
        body['max_output_tokens'] == described_class::MIN_OUTPUT_TOKENS &&
        body['store'] == false &&
        body['instructions'] == MessageTranslations::OpenaiSettings::DEFAULT_DEVELOPER_REPORT_INSTRUCTIONS &&
        body['input'] == [{
          'role' => 'user',
          'content' => [
            { 'type' => 'input_text', 'text' => 'Customer: Payment failed' },
            { 'type' => 'input_text', 'text' => 'Screenshot https://example.com/screenshot.png:' },
            { 'type' => 'input_image', 'image_url' => 'data:image/png;base64,iVBORw0KGgo=', 'detail' => 'high' }
          ]
        }]
    end.to_return(status: 200, body: completed_body, headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(hook: hook, context: 'Customer: Payment failed', images: images).perform

    expect(result).to eq('Отчёт')
    expect(request).to have_been_requested
  end

  it 'uses the instructions from the integration settings' do
    hook.settings['developer_report_instructions'] = 'Custom report instructions.'
    request = stub_request(:post, 'https://api.openai.com/v1/responses')
              .with { |req| JSON.parse(req.body)['instructions'] == 'Custom report instructions.' }
              .to_return(status: 200, body: completed_body, headers: { 'Content-Type' => 'application/json' })

    described_class.new(hook: hook, context: 'Customer: Hi', images: []).perform

    expect(request).to have_been_requested
  end

  it 'raises the error OpenAI returns' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(status: 400, body: { error: { message: 'Invalid image' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect { described_class.new(hook: hook, context: 'Customer: Hi', images: images).perform }
      .to raise_error(described_class::Error, 'Invalid image')
  end
end
