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
end
