class Integrations::OnyxMcp::Client
  class Error < StandardError; end

  PROTOCOL_VERSION = '2025-06-18'.freeze
  TIMEOUT_SECONDS = 60

  def initialize(hook:)
    @hook = hook
    @settings = hook.settings.to_h.with_indifferent_access
    @mcp_url = settings[:mcp_url].presence
    @api_token = settings[:api_token].presence
    @request_id = 0
  end

  def search_indexed_documents(query:, source_types:, limit:)
    validate_settings!
    initialize_session

    arguments = {
      query: query,
      limit: limit
    }
    arguments[:source_types] = source_types if source_types.present?

    result = call_search_indexed_documents(arguments)
    return result unless unsupported_argument_error?(result, 'limit')

    fallback_arguments = arguments.except(:limit)
    call_search_indexed_documents(fallback_arguments)
  end

  private

  attr_reader :hook, :settings, :mcp_url, :api_token
  attr_accessor :session_id

  def validate_settings!
    raise Error, 'Onyx MCP URL is not configured' if mcp_url.blank?
    raise Error, 'Onyx MCP API token is not configured' if api_token.blank?
  end

  def initialize_session
    response = post_json(jsonrpc_request('initialize', initialize_params))
    @session_id = response.headers['mcp-session-id'] || response.headers['Mcp-Session-Id']
    parse_json_rpc_response(response)

    post_json({
                jsonrpc: '2.0',
                method: 'notifications/initialized'
              })
  end

  def initialize_params
    {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: {
        name: 'chatwoot-community-onyx-mcp',
        version: '1.0.0'
      }
    }
  end

  def request(method, params)
    parse_json_rpc_response(post_json(jsonrpc_request(method, params)))
  end

  def call_search_indexed_documents(arguments)
    result = request('tools/call', {
                       name: 'search_indexed_documents',
                       arguments: arguments
                     })
    raise Error, tool_error_message(result) if tool_error?(result) && !unsupported_argument_error?(result, 'limit')

    result
  end

  def tool_error?(result)
    ActiveModel::Type::Boolean.new.cast(result&.dig('isError'))
  end

  def unsupported_argument_error?(result, argument_name)
    return false unless tool_error?(result)

    tool_error_message(result).include?('Unexpected keyword argument') &&
      tool_error_message(result).include?(argument_name)
  end

  def tool_error_message(result)
    content_items = result&.dig('content')
    Array(content_items).filter_map do |item|
      next unless item['type'] == 'text'

      item['text'].presence
    end.join("\n").presence || 'Onyx MCP tool call failed'
  end

  def jsonrpc_request(method, params)
    {
      jsonrpc: '2.0',
      id: next_request_id,
      method: method,
      params: params
    }
  end

  def next_request_id
    @request_id += 1
  end

  def post_json(body)
    connection.post(mcp_url) do |req|
      req.headers['Authorization'] = "Bearer #{api_token}"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json, text/event-stream'
      req.headers['MCP-Protocol-Version'] = PROTOCOL_VERSION if session_id.present?
      req.headers['Mcp-Session-Id'] = session_id if session_id.present?
      req.body = body.to_json
    end
  end

  def parse_json_rpc_response(response)
    return {} if response.success? && response.body.blank?

    payload = parse_response_body(response)

    unless response.success?
      message = payload.dig('error', 'message').presence || "Onyx MCP request failed with HTTP #{response.status}"
      raise Error, message
    end

    raise Error, payload.dig('error', 'message') if payload['error'].present?

    payload['result'] || payload
  end

  def parse_response_body(response)
    content_type = response.headers['content-type'].to_s
    return parse_sse_response(response.body) if content_type.include?('text/event-stream')

    JSON.parse(response.body.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def parse_sse_response(body)
    events = body.to_s.split(/\n{2,}/).filter_map do |event|
      data = event.lines.filter_map do |line|
        next unless line.start_with?('data:')

        line.sub(/\Adata:\s?/, '').strip
      end.join("\n")

      next if data.blank? || data == '[DONE]'

      JSON.parse(data)
    rescue JSON::ParserError
      nil
    end

    events.reverse.find { |event| event['result'].present? || event['error'].present? || event['id'].present? } || {}
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end
  end
end
