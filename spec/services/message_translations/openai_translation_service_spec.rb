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
  let(:unsupported_params_key) { format(Redis::Alfred::OPENAI_UNSUPPORTED_PARAMS, model: 'gpt-5.1', reasoning_effort: 'high') }

  before { Redis::Alfred.delete(unsupported_params_key) }
  after { Redis::Alfred.delete(unsupported_params_key) }

  # The raw API shape: no top-level output_text, a reasoning item before the message
  def translation_response(status: 'completed', text: 'Hello, I need help', incomplete_details: nil)
    body = {
      status: status,
      incomplete_details: incomplete_details,
      output: [
        { type: 'reasoning', summary: [] },
        { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: text }] }
      ]
    }
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def rejection(message, param)
    { status: 400, body: { error: { message: message, type: 'invalid_request_error', param: param, code: nil } }.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_responses(without:, rejected_with:)
    rejected = stub_request(:post, 'https://api.openai.com/v1/responses')
               .with { |req| JSON.parse(req.body).key?(without) }
               .to_return(rejected_with)
    accepted = stub_request(:post, 'https://api.openai.com/v1/responses')
               .with { |req| JSON.parse(req.body).exclude?(without) }
               .to_return(translation_response)
    [rejected, accepted]
  end

  def translate_twice
    2.times do
      expect(described_class.new(hook: hook, message: message, target_locale: 'en').perform).to eq('Hello, I need help')
    end
  end

  it 'translates content through the OpenAI Responses API using configured settings' do
    request = stub_request(:post, 'https://api.openai.com/v1/responses')
              .with do |req|
                body = JSON.parse(req.body)
                req.headers['Authorization'] == 'Bearer sk-test' &&
                  body['model'] == 'gpt-5.1' &&
                  body['reasoning'] == { 'effort' => 'high' } &&
                  body['max_output_tokens'] == 800 &&
                  body['temperature'].to_s == '0.1' &&
                  body['store'] == false &&
                  body['instructions'].include?('Custom translation instructions.') &&
                  body['input'].include?('Target language locale: en') &&
                  body['input'].include?('Hola, necesito ayuda')
              end
              .to_return(translation_response)

    result = described_class.new(hook: hook, message: message, target_locale: 'en').perform

    expect(result).to eq('Hello, I need help')
    expect(request).to have_been_requested
  end

  it 'rejects a translation cut off by the output token limit' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(translation_response(status: 'incomplete', text: 'Hello, I', incomplete_details: { reason: 'max_output_tokens' }))

    expect { described_class.new(hook: hook, message: message, target_locale: 'en').perform }.to(raise_error do |error|
      expect(error.class.name).to eq('MessageTranslations::OpenaiResponsesClient::Error')
      expect(error.message).to start_with('OpenAI ran out of output tokens')
    end)
  end

  it 'gives up after 60 seconds, before the web request that waits for it is cut off' do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(translation_response)
    connections = []
    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |connection| connections << connection }
    end

    described_class.new(hook: hook, message: message, target_locale: 'en').perform

    expect(connections.map { |connection| [connection.options.timeout, connection.options.open_timeout] }).to eq([[60, 10]])
  end

  it 'retries without a param the model rejects and skips it on later requests' do
    rejected, accepted = stub_responses(
      without: 'temperature',
      rejected_with: rejection("Unsupported parameter: 'temperature' is not supported with this model.", 'temperature')
    )

    translate_twice

    expect(rejected).to have_been_requested.once
    expect(accepted).to have_been_requested.twice
  end

  it 'drops a value the model rejects for that request only, so a corrected setting is sent again' do
    rejected, accepted = stub_responses(
      without: 'max_output_tokens',
      rejected_with: rejection("Invalid 'max_output_tokens': integer above maximum value.", 'max_output_tokens')
    )

    translate_twice

    expect(rejected).to have_been_requested.twice
    expect(accepted).to have_been_requested.twice
  end

  it 'remembers a rejected reasoning effort even when OpenAI calls it invalid' do
    rejected, accepted = stub_responses(
      without: 'reasoning',
      rejected_with: rejection("Invalid value: 'high'. Supported values are: 'low' and 'medium'.", 'reasoning.effort')
    )

    translate_twice

    expect(rejected).to have_been_requested.once
    expect(accepted).to have_been_requested.twice
  end
end
