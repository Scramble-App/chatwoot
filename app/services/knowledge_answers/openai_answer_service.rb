class KnowledgeAnswers::OpenaiAnswerService
  class Error < StandardError; end

  TIMEOUT_SECONDS = 30

  attr_reader :model

  def initialize(openai_hook:, onyx_hook:, conversation_context:, knowledge_context:, output_language:)
    @openai_hook = openai_hook
    @onyx_hook = onyx_hook
    @conversation_context = conversation_context.to_s
    @knowledge_context = knowledge_context.to_s
    @output_language = output_language.to_s
    @model = MessageTranslations::OpenaiSettings.model(openai_hook)
  end

  def perform
    parsed_response = make_request
    extract_output_text(parsed_response).presence || raise(Error, 'OpenAI returned an empty knowledge answer')
  end

  private

  attr_reader :openai_hook, :onyx_hook, :conversation_context, :knowledge_context, :output_language

  def make_request
    response = connection.post("#{Integrations::Openai::KeyValidator.api_base}/responses") do |req|
      req.headers['Authorization'] = "Bearer #{openai_hook.settings['api_key']}"
      req.headers['Content-Type'] = 'application/json'
      req.body = request_body.to_json
    end
    parsed_body = parse_response_body(response.body)

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI knowledge answer failed with HTTP #{response.status}"
  end

  def request_body
    body = {
      model: model,
      instructions: instructions,
      input: input_text,
      max_output_tokens: MessageTranslations::OpenaiSettings.max_output_tokens(openai_hook),
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_temperature!(body, openai_hook, model)

    reasoning_effort = MessageTranslations::OpenaiSettings.reasoning_effort(openai_hook)
    body[:reasoning] = { effort: reasoning_effort } if reasoning_effort != 'none' && MessageTranslations::OpenaiSettings.reasoning_supported?(model)

    body
  end

  def instructions
    [
      'Draft a customer support reply for an operator using the provided public conversation context and knowledge base excerpts.',
      "Output language must be #{output_language}. Ignore the customer language for the draft language. Return only text in the output language.",
      'The draft is for the operator to review; do not send it automatically.',
      KnowledgeAnswers::OnyxSettings.answer_guardrails(onyx_hook)
    ].join(' ')
  end

  def input_text
    <<~TEXT
      Reply tone/style instructions:
      #{KnowledgeAnswers::OnyxSettings.reply_tone_instructions(onyx_hook)}

      Public conversation context, oldest to newest:
      #{conversation_context}

      Knowledge base excerpts from Onyx:
      #{knowledge_context}
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
