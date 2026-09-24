class MessageTranslations::OpenaiSettings
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_MAX_OUTPUT_TOKENS = 1200
  # Leaves reasoning to the model's own default instead of sending an effort
  DEFAULT_REASONING_EFFORT = 'default'.freeze
  DEFAULT_TEMPERATURE = 0.2
  DEFAULT_REPLY_TONE_INSTRUCTIONS = 'Professional, clear, concise, friendly support tone.'.freeze
  DEFAULT_TRANSLATION_INSTRUCTIONS = [
    'Translate customer support messages into the requested target language.',
    'Preserve URLs, email addresses, names, code, placeholders, and line breaks where possible.',
    'Return only the translated message text.'
  ].join(' ').freeze
  DEFAULT_PREPARE_ANSWER_INSTRUCTIONS = [
    'Prepare operator replies for customer support conversations.',
    "Detect the customer's language from the customer message context and translate the operator draft into that language.",
    'Apply the configured tone of voice without changing the factual meaning of the draft.',
    'Preserve URLs, email addresses, names, code, markdown links, variables, placeholders, and line breaks where possible.',
    'Do not add facts, promises, greetings, signatures, or explanations that are not present in the operator draft.',
    'Return only the final prepared reply text.'
  ].join(' ').freeze
  DEFAULT_SUMMARY_INSTRUCTIONS = [
    'Summarize customer support conversations for internal operator handoff.',
    'Group separate customer issues as Question 1, Question 2, and so on, using equivalent headings in the output language.',
    'For each question, include: customer problem, agent replies or internal actions, result or current status, and recommended next step.',
    'Treat "Agent reply to customer" as a public response sent to the customer.',
    'Treat "Internal private note" as internal support work only; do not describe it as a customer-facing reply.',
    'Do not say support actions were not recorded when the context contains an Agent reply to customer or an Internal private note.',
    'Do not invent facts, promises, names, dates, or decisions that are not present in the conversation context.'
  ].join(' ').freeze

  class << self
    def hook_for(account)
      account.hooks.find_by(app_id: 'openai', status: 'enabled')
    end

    def translation_enabled?(hook)
      boolean_value(hook&.settings&.dig('translation_enabled'))
    end

    def auto_translate_incoming?(hook)
      boolean_value(hook&.settings&.dig('auto_translate_incoming'))
    end

    def model(hook)
      hook&.settings&.dig('translation_model').presence || DEFAULT_MODEL
    end

    # Any effort name is passed through, so new OpenAI values work without a code change;
    # OpenaiResponsesClient drops it when the model does not support it.
    def reasoning_effort(hook)
      value = hook&.settings&.dig('translation_reasoning_effort').to_s.strip.downcase
      value.match?(/\A[a-z_]+\z/) ? value : DEFAULT_REASONING_EFFORT
    end

    def max_output_tokens(hook)
      value = hook&.settings&.dig('translation_max_output_tokens').presence
      return DEFAULT_MAX_OUTPUT_TOKENS if value.blank?

      value.to_i.clamp(100, 10_000)
    end

    def temperature(hook)
      value = hook&.settings&.dig('translation_temperature').presence
      return DEFAULT_TEMPERATURE if value.blank?

      value.to_f.clamp(0.0, 2.0)
    end

    # Options are sent as configured; OpenaiResponsesClient drops and remembers the ones a model rejects
    def apply_model_options!(body, hook)
      effort = reasoning_effort(hook)
      body[:reasoning] = { effort: effort } unless effort == DEFAULT_REASONING_EFFORT
      body[:temperature] = temperature(hook)
      body
    end

    def reply_tone_instructions(hook)
      hook&.settings&.dig('reply_tone_instructions').presence || DEFAULT_REPLY_TONE_INSTRUCTIONS
    end

    def translation_instructions(hook)
      hook&.settings&.dig('translation_instructions').presence || DEFAULT_TRANSLATION_INSTRUCTIONS
    end

    def prepare_answer_instructions(hook)
      hook&.settings&.dig('prepare_answer_instructions').presence || DEFAULT_PREPARE_ANSWER_INSTRUCTIONS
    end

    def summary_instructions(hook, output_language:)
      [
        "Output language must be #{output_language}. Ignore the customer language for the summary language. Return only text in the output language.",
        hook&.settings&.dig('summary_instructions').presence || DEFAULT_SUMMARY_INSTRUCTIONS
      ].join(' ')
    end

    private

    def boolean_value(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
