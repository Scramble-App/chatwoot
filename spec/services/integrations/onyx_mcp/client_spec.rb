require 'rails_helper'

RSpec.describe Integrations::OnyxMcp::Client do
  let(:hook) do
    build(
      :integrations_hook,
      :onyx_mcp,
      settings: {
        'mcp_url' => 'https://cloud.onyx.app/mcp',
        'api_token' => 'onyx-token'
      }
    )
  end

  # Each example stubs the full MCP handshake (initialize, notification, tool call)
  # rubocop:disable RSpec/ExampleLength
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
    tool_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                   .with do |req|
                     body = JSON.parse(req.body)
                     req.headers['Mcp-Session-Id'] == 'session-1' &&
                       req.headers['Mcp-Protocol-Version'] == '2025-06-18' &&
                       body['method'] == 'tools/call' &&
                       body['params']['name'] == 'search_indexed_documents' &&
                       body['params']['arguments'] == {
                         'query' => 'invoice help',
                         'limit' => 5,
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

    result = described_class.new(hook: hook).search_indexed_documents(
      query: 'invoice help',
      source_types: %w[confluence jira],
      limit: 5
    )

    expect(result['documents'].first['content']).to eq('Invoice docs')
    expect(initialize_request).to have_been_requested
    expect(initialized_request).to have_been_requested
    expect(tool_request).to have_been_requested
  end

  it 'retries search without limit when the MCP server does not support the limit argument' do
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
    failed_tool_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                          .with do |req|
                            body = JSON.parse(req.body)
                            body['method'] == 'tools/call' &&
                              body['params']['arguments'].key?('limit')
                          end
                          .to_return(
                            status: 200,
                            body: {
                              jsonrpc: '2.0',
                              id: 2,
                              result: {
                                content: [
                                  {
                                    type: 'text',
                                    text: "limit\n  Unexpected keyword argument"
                                  }
                                ],
                                isError: true
                              }
                            }.to_json,
                            headers: { 'Content-Type' => 'application/json' }
                          )
    fallback_tool_request = stub_request(:post, 'https://cloud.onyx.app/mcp')
                            .with do |req|
                              body = JSON.parse(req.body)
                              body['method'] == 'tools/call' &&
                                body['params']['arguments'] == {
                                  'query' => 'investment help',
                                  'source_types' => %w[confluence jira]
                                }
                            end
                            .to_return(
                              status: 200,
                              body: {
                                jsonrpc: '2.0',
                                id: 3,
                                result: {
                                  structuredContent: {
                                    results: [
                                      { title: 'Investment guide', content: 'Investment docs' }
                                    ]
                                  }
                                }
                              }.to_json,
                              headers: { 'Content-Type' => 'application/json' }
                            )

    result = described_class.new(hook: hook).search_indexed_documents(
      query: 'investment help',
      source_types: %w[confluence jira],
      limit: 5
    )

    expect(result.dig('structuredContent', 'results').first['content']).to eq('Investment docs')
    expect(failed_tool_request).to have_been_requested
    expect(fallback_tool_request).to have_been_requested
  end
  # rubocop:enable RSpec/ExampleLength

  it 'waits up to 2 minutes for each MCP response and 10 seconds for the connection' do
    stub_request(:post, 'https://cloud.onyx.app/mcp')
      .to_return(status: 200, body: { jsonrpc: '2.0', id: 1, result: {} }.to_json, headers: { 'Content-Type' => 'application/json' })
    connections = []
    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |connection| connections << connection }
    end

    described_class.new(hook: hook).search_indexed_documents(query: 'invoice help', source_types: [], limit: 5)

    # initialize, notifications/initialized and tools/call
    expect(connections.map { |connection| [connection.options.timeout, connection.options.open_timeout] }).to eq([[120, 10]] * 3)
  end

  it 'explains when Onyx cannot be reached' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_raise(Net::OpenTimeout)

    expect { described_class.new(hook: hook).search_indexed_documents(query: 'invoice help', source_types: [], limit: 5) }
      .to(raise_error do |error|
        expect(error.class.name).to eq('Integrations::OnyxMcp::Client::Error')
        expect(error.message).to start_with("Couldn't connect to Onyx at cloud.onyx.app")
      end)
  end

  it 'explains when Onyx does not answer in time' do
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_raise(Net::ReadTimeout)

    expect { described_class.new(hook: hook).search_indexed_documents(query: 'invoice help', source_types: [], limit: 5) }
      .to(raise_error do |error|
        expect(error.class.name).to eq('Integrations::OnyxMcp::Client::Error')
        expect(error.message).to eq("Onyx didn't respond within 120 seconds")
      end)
  end

  it 'raises the search error that Onyx reports inside a successful result' do
    body = { jsonrpc: '2.0', id: 1,
             result: { structuredContent: { error: "Source type 'site' not found. Available: jira, web.", results: [] }, isError: false } }
    stub_request(:post, 'https://cloud.onyx.app/mcp').to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })

    expect { described_class.new(hook: hook).search_indexed_documents(query: 'invoice help', source_types: %w[jira site], limit: 5) }
      .to(raise_error do |error|
        expect(error.class.name).to eq('Integrations::OnyxMcp::Client::Error')
        expect(error.message).to eq("Onyx search failed: Source type 'site' not found. Available: jira, web.")
      end)
  end
end
