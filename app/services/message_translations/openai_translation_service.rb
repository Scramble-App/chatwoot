class MessageTranslations::OpenaiTranslationService
  class Error < StandardError; end

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

    text = MessageTranslations::OpenaiResponsesClient.output_text(make_request(source_text))
    text.presence || raise(Error, 'OpenAI returned an empty translation')
  end

  private

  attr_reader :hook, :message, :target_locale

  def make_request(source_text)
    response, parsed_body = client.create(request_body(source_text))

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI translation failed with HTTP #{response.status}"
  end

  # Manual translation runs inside the agent's web request, so it gets the shorter web request timeout
  def client
    MessageTranslations::OpenaiResponsesClient.new(
      api_key: hook.settings['api_key'],
      timeout: MessageTranslations::OpenaiResponsesClient::WEB_REQUEST_TIMEOUT_SECONDS
    )
  end

  def request_body(source_text)
    body = {
      model: model,
      instructions: instructions,
      input: input_text(source_text),
      max_output_tokens: MessageTranslations::OpenaiSettings.max_output_tokens(hook),
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_model_options!(body, hook)
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
end
