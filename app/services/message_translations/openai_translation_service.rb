class MessageTranslations::OpenaiTranslationService
  class Error < StandardError; end

  TIMEOUT_SECONDS = 30

  attr_reader :model

  def self.source_text_for(message)
    email = message.content_attributes&.with_indifferent_access&.dig(:email)
    email_text = email&.dig(:textContent, :full)
    email_html = email&.dig(:htmlContent, :full)

    email_text.presence || message.processed_message_content.presence || message.content.presence || email_html.presence
  end

  def initialize(hook:, message:, target_locale:)
    @hook = hook
    @message = message
    @target_locale = target_locale
    @model = MessageTranslations::OpenaiSettings.model(hook)
  end

  def perform
    source_text = self.class.source_text_for(message)
    return if source_text.blank?

    parsed_response = make_request(source_text)
    extract_output_text(parsed_response).presence || raise(Error, 'OpenAI returned an empty translation')
  end

  private

  attr_reader :hook, :message, :target_locale

  def make_request(source_text)
    response = connection.post("#{Integrations::Openai::KeyValidator.api_base}/responses") do |req|
      req.headers['Authorization'] = "Bearer #{hook.settings['api_key']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = request_body(source_text).to_json
    end
    parsed_body = parse_response_body(response.body)

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI translation failed with HTTP #{response.status}"
  end

  def request_body(source_text)
    body = {
      model: model,
      instructions: instructions,
      input: input_text(source_text),
      max_output_tokens: MessageTranslations::OpenaiSettings.max_output_tokens(hook),
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_temperature!(body, hook, model)

    reasoning_effort = MessageTranslations::OpenaiSettings.reasoning_effort(hook)
    body[:reasoning] = { effort: reasoning_effort } if reasoning_effort != 'none' && MessageTranslations::OpenaiSettings.reasoning_supported?(model)

    body
  end

  def instructions
    MessageTranslations::OpenaiSettings.translation_instructions(hook)
  end

  def input_text(source_text)
    <<~TEXT
      Target language locale: #{target_locale}

      Message:
      #{source_text}
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
