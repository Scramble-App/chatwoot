# Posts to the OpenAI Responses API. Models differ in which tuning params they accept (e.g. reasoning
# models reject temperature), so a rejected optional param is dropped and the request is retried without it.
# An "Unsupported" rejection is remembered per model, reasoning effort and service tier, so later requests skip that param up front.
class MessageTranslations::OpenaiResponsesClient
  class Error < StandardError; end

  # AI generations run in background jobs, so slow reasoning models get up to 2 minutes
  TIMEOUT_SECONDS = 120
  # An agent's web request waits for these calls, so they must end before rack-timeout (90 s) aborts it
  WEB_REQUEST_TIMEOUT_SECONDS = 60
  # A reachable OpenAI accepts the connection in well under a second; waiting longer only delays the error
  CONNECT_TIMEOUT_SECONDS = 10
  OPTIONAL_PARAMS = %w[temperature top_p reasoning service_tier max_output_tokens].freeze
  # The memory key includes the effort and the tier, so a rejected value of these is remembered whatever the error says
  VALUE_KEYED_PARAMS = %w[reasoning service_tier].freeze

  # The reply text, or nil when there is none. Raises Error when OpenAI stopped early, so a cut-off reply is never used.
  # Raw API JSON has no top-level output_text (only the SDKs and some proxies add it), and reasoning items are skipped.
  def self.output_text(parsed_body)
    raise Error, unfinished_message(parsed_body) if %w[incomplete failed].include?(parsed_body['status'])
    return parsed_body['output_text'] if parsed_body['output_text'].present?

    text = message_part(parsed_body, 'output_text')&.dig('text')
    return text if text.present?

    refusal = message_part(parsed_body, 'refusal')
    raise Error, "OpenAI declined to answer: #{refusal['refusal']}" if refusal

    nil
  end

  def self.message_part(parsed_body, type)
    parts = Array(parsed_body['output']).select { |item| item['type'] == 'message' }.flat_map { |item| Array(item['content']) }
    parts.find { |part| part['type'] == type }
  end

  def self.unfinished_message(parsed_body)
    return "OpenAI failed to answer: #{parsed_body.dig('error', 'message')}" if parsed_body['status'] == 'failed'

    reason = parsed_body.dig('incomplete_details', 'reason')
    return "OpenAI stopped before finishing the reply (#{reason})" unless reason == 'max_output_tokens'

    "OpenAI ran out of output tokens before finishing the reply. Raise 'Translation max output tokens' or lower the reasoning effort"
  end
  private_class_method :message_part, :unfinished_message

  def initialize(api_key:, timeout: TIMEOUT_SECONDS)
    @api_key = api_key
    @timeout = timeout
  end

  # Returns the HTTP response and its parsed JSON body.
  def create(body)
    request_body = body.except(*unsupported_params(body).map(&:to_sym))

    loop do
      response = post(request_body)
      parsed_body = parse_response_body(response.body)
      rejected_param = rejected_optional_param(response, parsed_body, request_body)
      return [response, parsed_body] unless rejected_param

      Rails.logger.warn("[openai-responses] #{body[:model]} rejected '#{rejected_param}', retried without it: #{parsed_body.dig('error', 'message')}")
      remember_unsupported_param(body, rejected_param) if VALUE_KEYED_PARAMS.include?(rejected_param) || unsupported_error?(parsed_body)
      request_body = request_body.except(rejected_param.to_sym)
    end
  end

  private

  attr_reader :api_key, :timeout

  # Network failures are raised as Error, so the agent sees why the request failed
  def post(request_body)
    connection.post("#{Integrations::Openai::KeyValidator.api_base}/responses") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.headers['Content-Type'] = 'application/json'
      req.body = request_body.to_json
    end
  rescue Faraday::TimeoutError
    raise Error, "OpenAI didn't respond within #{timeout} seconds. Try a lower 'Translation reasoning effort'"
  rescue Faraday::ConnectionFailed, Faraday::SSLError => e
    raise Error, "Couldn't connect to OpenAI: #{e.message}"
  end

  # OpenAI names the rejected field in error.param (e.g. "temperature" or "reasoning.effort"); some errors only quote it in the message.
  def rejected_optional_param(response, parsed_body, request_body)
    return unless response.status == 400

    error = parsed_body['error'] || {}
    param = (error['param'].presence || error['message'].to_s[/'([a-z_.]+)'/, 1]).to_s.split('.').first
    param if OPTIONAL_PARAMS.include?(param) && request_body.key?(param.to_sym)
  end

  # "Unsupported parameter/value" is a lasting model trait, and so is a rejected effort or tier (the memory key includes them).
  # Other rejections (e.g. a value above the model limit) skip this request only.
  def unsupported_error?(parsed_body)
    parsed_body.dig('error', 'message').to_s.start_with?('Unsupported')
  end

  def unsupported_params(body)
    Redis::Alfred.get(unsupported_params_key(body)).to_s.split(',')
  end

  def remember_unsupported_param(body, param)
    Redis::Alfred.set(unsupported_params_key(body), (unsupported_params(body) | [param]).join(','))
  end

  # Requests without a service tier keep the key they had before tiers were supported
  def unsupported_params_key(body)
    key = format(Redis::Alfred::OPENAI_UNSUPPORTED_PARAMS, model: body[:model], reasoning_effort: body.dig(:reasoning, :effort) || 'default')
    body[:service_tier] ? "#{key}::#{body[:service_tier]}" : key
  end

  def parse_response_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = timeout
      f.options.open_timeout = CONNECT_TIMEOUT_SECONDS
    end
  end
end
