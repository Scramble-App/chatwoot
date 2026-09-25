class ConversationSummaries::OpenaiSummaryService
  class Error < StandardError; end

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
    response, parsed_body = MessageTranslations::OpenaiResponsesClient.new(api_key: hook.settings['api_key']).create(request_body)

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

    MessageTranslations::OpenaiSettings.apply_model_options!(body, hook)
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
end
