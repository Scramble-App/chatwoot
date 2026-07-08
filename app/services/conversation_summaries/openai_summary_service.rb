class ConversationSummaries::OpenaiSummaryService
  class Error < StandardError; end

  TIMEOUT_SECONDS = 30

  attr_reader :model

  def initialize(hook:, conversation_context:, output_language:)
    @hook = hook
    @conversation_context = conversation_context.to_s
    @output_language = output_language.to_s
    @model = MessageTranslations::OpenaiSettings.model(hook)
  end

  def perform
    parsed_response = make_request
    extract_output_text(parsed_response).presence || raise(Error, 'OpenAI returned an empty conversation summary')
  end

  private

  attr_reader :hook, :conversation_context, :output_language

  def make_request
    response = connection.post("#{Integrations::Openai::KeyValidator.api_base}/responses") do |req|
      req.headers['Authorization'] = "Bearer #{hook.settings['api_key']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = request_body.to_json
    end
    parsed_body = parse_response_body(response.body)

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI conversation summary failed with HTTP #{response.status}"
  end

  def request_body
    body = {
      model: model,
      instructions: instructions,
      input: input_text,
      max_output_tokens: MessageTranslations::OpenaiSettings.max_output_tokens(hook),
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_temperature!(body, hook, model)

    reasoning_effort = MessageTranslations::OpenaiSettings.reasoning_effort(hook)
    body[:reasoning] = { effort: reasoning_effort } if reasoning_effort != 'none' && MessageTranslations::OpenaiSettings.reasoning_supported?(model)

    body
  end

  def instructions
    MessageTranslations::OpenaiSettings.summary_instructions(hook, output_language: output_language)
  end

  def input_text
    <<~TEXT
      Reply tone/style instructions:
      #{MessageTranslations::OpenaiSettings.reply_tone_instructions(hook)}

      Conversation context, oldest to newest:
      #{conversation_context}
    TEXT
  end

  def extract_output_text(parsed_response)
    return parsed_response['output_text'] if parsed_response['output_text'].present?

    parsed_response['output']&.each do |item|
      item['content']&.each do |content_item|
        return content_item['text'] if content_item['text'].present?
      end
    end

    nil
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
