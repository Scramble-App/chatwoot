require 'rails_helper'

RSpec.describe MessageTranslations::OpenaiResponsesClient do
  def message_item(*parts)
    { 'type' => 'message', 'role' => 'assistant', 'status' => 'completed', 'content' => parts }
  end

  def expect_client_error(message, &)
    expect(&).to(raise_error do |error|
      expect(error.class.name).to eq('MessageTranslations::OpenaiResponsesClient::Error')
      expect(error.message).to eq(message)
    end)
  end

  describe '.output_text' do
    it 'reads the message text of a raw API response and skips reasoning' do
      body = {
        'status' => 'completed',
        'output' => [
          { 'type' => 'reasoning', 'summary' => [], 'content' => [{ 'type' => 'reasoning_text', 'text' => 'Thinking about it' }] },
          message_item({ 'type' => 'output_text', 'text' => 'Hello, I need help', 'annotations' => [] })
        ]
      }

      expect(described_class.output_text(body)).to eq('Hello, I need help')
    end

    it 'returns nil when there is no reply text' do
      expect(described_class.output_text({ 'status' => 'completed', 'output' => [{ 'type' => 'reasoning', 'summary' => [] }] })).to be_nil
    end

    it 'rejects a reply cut off by the output token limit, even with partial text' do
      body = {
        'status' => 'incomplete',
        'incomplete_details' => { 'reason' => 'max_output_tokens' },
        'output' => [message_item({ 'type' => 'output_text', 'text' => 'Hello, I ne' })]
      }

      expect_client_error(
        "OpenAI ran out of output tokens before finishing the reply. Raise 'Translation max output tokens' or lower the reasoning effort"
      ) { described_class.output_text(body) }
    end

    it 'rejects a reply stopped for another reason' do
      body = { 'status' => 'incomplete', 'incomplete_details' => { 'reason' => 'content_filter' }, 'output' => [] }

      expect_client_error('OpenAI stopped before finishing the reply (content_filter)') { described_class.output_text(body) }
    end

    it 'rejects a failed response' do
      body = { 'status' => 'failed', 'error' => { 'code' => 'server_error', 'message' => 'The server had an error' }, 'output' => [] }

      expect_client_error('OpenAI failed to answer: The server had an error') { described_class.output_text(body) }
    end

    it 'explains a refusal instead of reporting an empty reply' do
      body = { 'status' => 'completed', 'output' => [message_item({ 'type' => 'refusal', 'refusal' => "I can't help with that." })] }

      expect_client_error("OpenAI declined to answer: I can't help with that.") { described_class.output_text(body) }
    end
  end

  describe '#create' do
    let(:connections) { [] }

    before do
      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |connection| connections << connection }
      end
    end

    def create(timeout: described_class::TIMEOUT_SECONDS)
      described_class.new(api_key: 'openai-key', timeout: timeout).create(model: 'gpt-6-luna', input: 'Hello')
    end

    it 'waits up to 2 minutes for OpenAI and 10 seconds for the connection' do
      stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 200, body: {}.to_json)

      create

      expect(connections.map { |connection| [connection.options.timeout, connection.options.open_timeout] }).to eq([[120, 10]])
    end

    it 'uses a shorter timeout when asked to' do
      stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 200, body: {}.to_json)

      create(timeout: 60)

      expect(connections.map { |connection| connection.options.timeout }).to eq([60])
    end

    it 'explains when OpenAI does not answer in time' do
      stub_request(:post, 'https://api.openai.com/v1/responses').to_raise(Net::ReadTimeout)

      expect_client_error("OpenAI didn't respond within 120 seconds. Try a lower 'Translation reasoning effort'") { create }
    end

    it 'explains when OpenAI cannot be reached' do
      stub_request(:post, 'https://api.openai.com/v1/responses').to_raise(Net::OpenTimeout)

      expect { create }.to(raise_error do |error|
        expect(error.class.name).to eq('MessageTranslations::OpenaiResponsesClient::Error')
        expect(error.message).to start_with("Couldn't connect to OpenAI:")
      end)
    end
  end
end
