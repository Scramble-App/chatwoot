# Asks OpenAI for the question to search in Onyx. The conversation itself is too long for a search query (Onyx accepts
# at most 2048 characters) and full of signatures, quoted emails and links, while a focused question finds better documents.
class KnowledgeAnswers::OpenaiSearchQuestionService
  class Error < StandardError; end

  # The question needs little reasoning, and a high configured effort would add up to a minute before the search starts
  REASONING_EFFORT = 'low'.freeze
  FASTER_EFFORTS = %w[none minimal low].freeze
  INSTRUCTIONS = [
    'Analyze the support conversation with the customer and write the question for the model that answers from the company knowledge base.',
    "Focus on the customer's latest questions that are still unresolved.",
    'Ignore questions that an agent already answered or that were resolved earlier in the conversation.',
    'Write one self-contained question, in one to three sentences; if several questions are still open, include all of them.',
    'Include the details needed to understand it, such as the product, feature, error or what the customer already tried.',
    'Write the question in English.',
    'Leave out personal data such as names, email addresses, phone numbers, and account, card or transaction numbers.',
    'Return only the question.'
  ].join(' ').freeze

  def initialize(openai_hook:, onyx_hook:, conversation_context:)
    @openai_hook = openai_hook
    @onyx_hook = onyx_hook
    @conversation_context = conversation_context.to_s
  end

  def perform
    text = MessageTranslations::OpenaiResponsesClient.output_text(make_request)
    text.to_s.strip.presence || raise(Error, 'OpenAI returned an empty knowledge base search question')
  end

  private

  attr_reader :openai_hook, :onyx_hook, :conversation_context

  def make_request
    response, parsed_body = MessageTranslations::OpenaiResponsesClient.new(api_key: openai_hook.settings['api_key']).create(request_body)

    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI search question failed with HTTP #{response.status}"
  end

  def request_body
    body = {
      model: MessageTranslations::OpenaiSettings.model(openai_hook),
      instructions: [INSTRUCTIONS, KnowledgeAnswers::OnyxSettings.search_question_instructions(onyx_hook)].compact.join(' '),
      input: "Public conversation context, oldest to newest:\n#{conversation_context}",
      max_output_tokens: MessageTranslations::OpenaiSettings.max_output_tokens(openai_hook),
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_model_options!(body, openai_hook)
    body.merge(reasoning: { effort: reasoning_effort })
  end

  def reasoning_effort
    effort = MessageTranslations::OpenaiSettings.reasoning_effort(openai_hook)
    FASTER_EFFORTS.include?(effort) ? effort : REASONING_EFFORT
  end
end
