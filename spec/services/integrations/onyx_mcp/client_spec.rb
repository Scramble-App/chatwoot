require 'rails_helper'

RSpec.describe Integrations::OnyxMcp::Client do
  let(:mcp_url) { 'https://cloud.onyx.app/mcp' }
  let(:hook) do
    build(
      :integrations_hook,
      :onyx_mcp,
      settings: {
        'mcp_url' => mcp_url,
        'api_token' => 'onyx-token'
      }
    )
  end

  def stub_handshake
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .with { |req| JSON.parse(req.body)['method'] == 'initialize' }
      .to_return(
        status: 200,
        body: { jsonrpc: '2.0', id: 1, result: { protocolVersion: '2025-06-18', capabilities: {} } }.to_json,
        headers: { 'Content-Type' => 'application/json', 'Mcp-Session-Id' => 'session-1' }
      )
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .with { |req| JSON.parse(req.body)['method'] == 'notifications/initialized' }
      .to_return(status: 202, body: '')
  end

  def stub_search(response)
    stub_handshake
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .with { |req| JSON.parse(req.body)['method'] == 'tools/call' }
      .to_return(response)
  end

  def json_response(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def search(source_types: [])
    described_class.new(hook: hook).search_indexed_documents(query: 'invoice help', source_types: source_types)
  end

  def expect_onyx_error(message)
    expect { search }.to(raise_error do |error|
      expect(error.class.name).to eq('Integrations::OnyxMcp::Client::Error')
      expect(error.message).to eq(message)
    end)
  end

  it 'initializes an MCP session and calls search_indexed_documents' do
    initialize_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                         .with do |req|
                           body = JSON.parse(req.body)
                           req.headers['Authorization'] == 'Bearer onyx-token' &&
                             body['method'] == 'initialize' &&
                             body['params']['protocolVersion'] == '2025-06-18'
                         end
                         .to_return(
                           status: 200,
                           body: { jsonrpc: '2.0', id: 1, result: { protocolVersion: '2025-06-18', capabilities: {} } }.to_json,
                           headers: { 'Content-Type' => 'application/json', 'Mcp-Session-Id' => 'session-1' }
                         )
    initialized_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                          .with do |req|
                            body = JSON.parse(req.body)
                            req.headers['Mcp-Session-Id'] == 'session-1' &&
                              body['method'] == 'notifications/initialized'
                          end
                          .to_return(status: 202, body: '')
    # Onyx rejects arguments its tool does not define, so only query and source types are sent
    tool_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                   .with do |req|
                     body = JSON.parse(req.body)
                     req.headers['Mcp-Session-Id'] == 'session-1' &&
                       req.headers['Mcp-Protocol-Version'] == '2025-06-18' &&
                       body['method'] == 'tools/call' &&
                       body['params']['name'] == 'search_indexed_documents' &&
                       body['params']['arguments'] == {
                         'query' => 'invoice help',
                         'source_types' => %w[confluence jira]
                       }
                   end
                   .to_return(
                     status: 200,
                     body: {
                       jsonrpc: '2.0',
                       id: 2,
                       result: {
                         documents: [
                           { semantic_identifier: 'Billing guide', content: 'Invoice docs' }
                         ]
                       }
                     }.to_json,
                     headers: { 'Content-Type' => 'application/json' }
                   )

    result = search(source_types: %w[confluence jira])

    expect(result['documents'].first['content']).to eq('Invoice docs')
    expect(initialize_request).to have_been_requested
    expect(initialized_request).to have_been_requested
    expect(tool_request).to have_been_requested
  end

  it 'reads the result from an event stream with CRLF line endings and a notification before the result' do
    events = [
      "event: message\r\ndata: #{{ jsonrpc: '2.0', method: 'notifications/message', params: { level: 'info', data: 'searching' } }.to_json}",
      "event: message\r\ndata: #{{ jsonrpc: '2.0', id: 2, result: { structuredContent: { results: [{ content: 'Invoice docs' }] } } }.to_json}"
    ]
    stub_search(status: 200, body: "#{events.join("\r\n\r\n")}\r\n\r\n", headers: { 'Content-Type' => 'text/event-stream' })

    expect(search.dig('structuredContent', 'results').first['content']).to eq('Invoice docs')
  end

  it 'cuts the query to the 2048 characters Onyx accepts' do
    stub_handshake
    tool_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                   .with { |req| JSON.parse(req.body).dig('params', 'arguments', 'query')&.length == 2048 }
                   .to_return(json_response({ jsonrpc: '2.0', id: 2, result: { structuredContent: { results: [] } } }))

    described_class.new(hook: hook).search_indexed_documents(query: 'a' * 3000, source_types: [])

    expect(tool_request).to have_been_requested
  end

  context 'with whitespace around the configured URL' do
    let(:mcp_url) { " https://cloud.onyx.app/mcp\n" }

    it 'calls the URL without it' do
      stub_search(json_response({ jsonrpc: '2.0', id: 2, result: { structuredContent: { results: [] } } }))

      expect(search).to eq('structuredContent' => { 'results' => [] })
    end
  end

  it 'shows the tool error when Onyx rejects the arguments' do
    stub_search(json_response({ jsonrpc: '2.0', id: 2,
                                result: { content: [{ type: 'text', text: "source_types\n  Unexpected keyword argument" }], isError: true } }))

    expect_onyx_error("source_types\n  Unexpected keyword argument")
  end

  it 'raises the search error that Onyx reports inside a successful result' do
    body = { jsonrpc: '2.0', id: 1,
             result: { structuredContent: { error: "Source type 'site' not found. Available: jira, web.", results: [] }, isError: false } }
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_return(json_response(body))

    expect_onyx_error("Onyx search failed: Source type 'site' not found. Available: jira, web.")
  end

  it 'raises the search error that Onyx reports only in the text content' do
    error_payload = { error: "Source type 'site' not found. Available: jira, web.", results: [] }
    stub_search(json_response({ jsonrpc: '2.0', id: 2, result: { content: [{ type: 'text', text: error_payload.to_json }], isError: false } }))

    expect_onyx_error("Onyx search failed: Source type 'site' not found. Available: jira, web.")
  end

  it 'explains that Onyx rejected the API token' do
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .to_return(json_response({ error: 'invalid_token', error_description: 'The access token expired' }, status: 401))

    expect_onyx_error('Onyx rejected the API token (HTTP 401): invalid_token: The access token expired')
  end

  it 'explains a redirect instead of reading it as an empty result' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_return(status: 307, headers: { 'Location' => 'https://cloud.onyx.app/mcp/' })

    expect_onyx_error('Onyx redirected to https://cloud.onyx.app/mcp/. Update the MCP URL')
  end

  it 'explains a page that is not an MCP response, e.g. a login page' do
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .to_return(status: 200, body: '<html>Sign in</html>', headers: { 'Content-Type' => 'text/html' })

    expect_onyx_error('Onyx returned a non-MCP response (HTTP 200, text/html). Check the MCP URL')
  end

  it 'explains an empty search response instead of reading it as no results' do
    stub_search(status: 200, body: '', headers: { 'Content-Type' => 'application/json' })

    expect_onyx_error('Onyx returned a non-MCP response (HTTP 200, application/json). Check the MCP URL')
  end

  it 'waits up to 2 minutes for each MCP response and 10 seconds for the connection' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_return(json_response({ jsonrpc: '2.0', id: 1, result: {} }))
    connections = []
    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |connection| connections << connection }
    end

    search

    # initialize, notifications/initialized and tools/call
    expect(connections.map { |connection| [connection.options.timeout, connection.options.open_timeout] }).to eq([[120, 10]] * 3)
  end

  it 'explains when Onyx cannot be reached' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_raise(Net::OpenTimeout)

    expect { search }.to(raise_error do |error|
      expect(error.class.name).to eq('Integrations::OnyxMcp::Client::Error')
      expect(error.message).to start_with("Couldn't connect to Onyx at cloud.onyx.app")
    end)
  end

  it 'explains when the Onyx certificate is not accepted' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_raise(OpenSSL::SSL::SSLError.new('certificate has expired'))

    expect_onyx_error("Couldn't connect to Onyx at cloud.onyx.app: certificate has expired")
  end

  it 'explains when Onyx does not answer in time' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_raise(Net::ReadTimeout)

    expect_onyx_error("Onyx didn't respond within 120 seconds")
  end
end
