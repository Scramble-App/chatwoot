# Posts to the OpenAI Responses API. Models differ in which tuning params they accept (e.g. reasoning
# models reject temperature), so a rejected optional param is dropped and the request is retried without it.
# An "Unsupported" rejection is remembered per model and reasoning effort, so later requests skip that param up front.
class MessageTranslations::OpenaiResponsesClient
  TIMEOUT_SECONDS = 30
  OPTIONAL_PARAMS = %w[temperature top_p reasoning max_output_tokens].freeze

  def initialize(api_key:)
    @api_key = api_key
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
      remember_unsupported_param(body, rejected_param) if rejected_param == 'reasoning' || unsupported_error?(parsed_body)
      request_body = request_body.except(rejected_param.to_sym)
    end
  end

  private

  attr_reader :api_key

  def post(request_body)
    connection.post("#{Integrations::Openai::KeyValidator.api_base}/responses") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.headers['Content-Type'] = 'application/json'
      req.body = request_body.to_json
    end
  end

  # OpenAI names the rejected field in error.param (e.g. "temperature" or "reasoning.effort"); some errors only quote it in the message.
  def rejected_optional_param(response, parsed_body, request_body)
    return unless response.status == 400

    error = parsed_body['error'] || {}
    param = (error['param'].presence || error['message'].to_s[/'([a-z_.]+)'/, 1]).to_s.split('.').first
    param if OPTIONAL_PARAMS.include?(param) && request_body.key?(param.to_sym)
  end

  # "Unsupported parameter/value" is a lasting model trait, and so is a rejected effort (the memory key includes it).
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

  def unsupported_params_key(body)
    format(Redis::Alfred::OPENAI_UNSUPPORTED_PARAMS, model: body[:model], reasoning_effort: body.dig(:reasoning, :effort) || 'default')
  end

  def parse_response_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end
  end
end
