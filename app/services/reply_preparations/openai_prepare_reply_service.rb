class ReplyPreparations::OpenaiPrepareReplyService
  class Error < StandardError; end

  attr_reader :model

  def initialize(hook:, content:, customer_context:)
    @hook = hook
    @content = content.to_s
    @customer_context = customer_context.to_s
    @model = MessageTranslations::OpenaiSettings.model(hook)
  end

  def perform
    text = MessageTranslations::OpenaiResponsesClient.output_text(make_request)
    text.presence || raise(Error, 'OpenAI returned an empty prepared reply')
  end

  private

  attr_reader :hook, :content, :customer_context

  def make_request
    response, parsed_body = MessageTranslations::OpenaiResponsesClient.new(api_key: hook.settings['api_key']).create(request_body)

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI reply preparation failed with HTTP #{response.status}"
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
    MessageTranslations::OpenaiSettings.prepare_answer_instructions(hook)
  end

  def input_text
    <<~TEXT
      Reply tone/style instructions:
      #{MessageTranslations::OpenaiSettings.reply_tone_instructions(hook)}

      Customer message context, oldest to newest:
      #{customer_context}

      Operator draft:
      #{content}
    TEXT
  end
end
