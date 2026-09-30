class Integrations::OnyxMcp::Client
  class Error < StandardError; end

  PROTOCOL_VERSION = '2025-06-18'.freeze
  TIMEOUT_SECONDS = 120
  # A reachable Onyx accepts the connection in well under a second; waiting longer only delays the error
  CONNECT_TIMEOUT_SECONDS = 10
  # Onyx rejects longer queries (its SearchRequest allows at most 2048 characters)
  QUERY_CHARACTER_LIMIT = 2048

  def initialize(hook:)
    @hook = hook
    @settings = hook.settings.to_h.with_indifferent_access
    @mcp_url = settings[:mcp_url].to_s.strip.presence
    @api_token = settings[:api_token].to_s.strip.presence
    @request_id = 0
  end

  # Onyx rejects arguments its tool does not define and has dropped `limit` before, so only query and source types are sent
  def search_indexed_documents(query:, source_types:)
    validate_settings!
    initialize_session

    arguments = { query: query.to_s.first(QUERY_CHARACTER_LIMIT) }
    arguments[:source_types] = source_types if source_types.present?
    call_search_indexed_documents(arguments)
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
    raise Error, tool_error_message(result) if tool_error?(result)

    # Onyx reports some search failures, e.g. an unknown source type, inside a result that is not flagged as an error
    search_error = search_error_from(result)
    raise Error, "Onyx search failed: #{search_error}" if search_error

    result
  end

  def tool_error?(result)
    ActiveModel::Type::Boolean.new.cast(result['isError'])
  end

  def tool_error_message(result)
    content_items = result['content']
    Array(content_items).filter_map do |item|
      next unless item['type'] == 'text'

      item['text'].presence
    end.join("\n").presence || 'Onyx MCP tool call failed'
  end

  # The error is in structuredContent, or only in the JSON text content when the tool has no output schema
  def search_error_from(result)
    payloads = [result['structuredContent'], *Array(result['content']).map { |item| parse_text_content(item) }]
    payloads.find { |payload| payload.is_a?(Hash) && payload['error'].present? }&.dig('error')
  end

  def parse_text_content(item)
    return unless item.is_a?(Hash) && item['type'] == 'text'

    JSON.parse(item['text'].to_s)
  rescue JSON::ParserError
    nil
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
    with_network_errors do
      connection.post(mcp_url) do |req|
        req.headers['Authorization'] = "Bearer #{api_token}"
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json, text/event-stream'
        req.headers['MCP-Protocol-Version'] = PROTOCOL_VERSION if session_id.present?
        req.headers['Mcp-Session-Id'] = session_id if session_id.present?
        req.body = body.to_json
      end
    end
  end

  # Network failures are raised as Error, so the agent sees why the knowledge answer failed
  def with_network_errors
    yield
  rescue Faraday::ConnectionFailed, Faraday::SSLError => e
    raise Error, "Couldn't connect to Onyx at #{URI(mcp_url).host}: #{e.message}"
  rescue Faraday::TimeoutError
    raise Error, "Onyx didn't respond within #{TIMEOUT_SECONDS} seconds"
  end

  # Anything but a JSON-RPC result raises, so a login page, a proxy or a wrong URL is not read as "no results"
  def parse_json_rpc_response(response)
    raise Error, "Onyx redirected to #{response.headers['location']}. Update the MCP URL" if response.status.between?(300, 399)

    payload = parse_response_body(response)
    raise Error, http_error_message(response, payload) unless response.success?

    error_message = error_message_from(payload)
    raise Error, error_message if error_message
    return payload['result'] if payload['result'].is_a?(Hash)

    content_type = response.headers['content-type'].presence || 'no content type'
    raise Error, "Onyx returned a non-MCP response (HTTP #{response.status}, #{content_type}). Check the MCP URL"
  end

  def http_error_message(response, payload)
    message = if [401, 403].include?(response.status)
                "Onyx rejected the API token (HTTP #{response.status})"
              else
                "Onyx MCP request failed with HTTP #{response.status}"
              end
    detail = error_message_from(payload)
    detail ? "#{message}: #{detail}" : message
  end

  # JSON-RPC errors are objects with a message; OAuth errors (e.g. an expired token) are a code with an optional description
  def error_message_from(payload)
    error = payload['error']
    return if error.blank?
    return error['message'].presence || error.to_json if error.is_a?(Hash)

    [error, payload['error_description']].compact_blank.join(': ')
  end

  def parse_response_body(response)
    content_type = response.headers['content-type'].to_s
    parsed = content_type.include?('text/event-stream') ? parse_sse_response(response.body) : JSON.parse(response.body.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def parse_sse_response(body)
    # sse-starlette ends lines with CRLF, and a stream may carry notifications before the response
    events = body.to_s.gsub(/\r\n?/, "\n").split(/\n{2,}/).filter_map do |event|
      data = event.lines.filter_map do |line|
        next unless line.start_with?('data:')

        line.sub(/\Adata:\s?/, '').strip
      end.join("\n")

      next if data.blank? || data == '[DONE]'

      parsed = JSON.parse(data)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    events.reverse.find { |event| event['result'].present? || event['error'].present? || event['id'].present? } || {}
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = CONNECT_TIMEOUT_SECONDS
    end
  end
end
