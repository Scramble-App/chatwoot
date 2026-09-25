require 'rails_helper'

RSpec.describe MessageTranslations::OpenaiResponsesClient do
  it 'waits up to 60 seconds for OpenAI' do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 200, body: {}.to_json)
    connections = []
    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |connection| connections << connection }
    end

    described_class.new(api_key: 'openai-key').create(model: 'gpt-6-luna', input: 'Hello')

    expect(connections.map { |connection| [connection.options.timeout, connection.options.open_timeout] }).to eq([[60, 60]])
  end
end
