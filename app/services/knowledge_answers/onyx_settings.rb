class KnowledgeAnswers::OnyxSettings
  DEFAULT_QUERY_TEMPLATE = <<~TEXT.squish
    Please help answer the customer support question using the indexed knowledge base.
    Use this public conversation context:
    {{conversation_context}}
  TEXT
  DEFAULT_RESULT_LIMIT = 5
  DEFAULT_ANSWER_GUARDRAILS = <<~TEXT.squish.freeze
    Use only the provided knowledge base excerpts. Do not invent facts, policy details, product behavior, links, prices, dates, or promises. If the knowledge base does not contain enough information, say what is missing and suggest that the agent verify it internally.
  TEXT
  DEFAULT_REPLY_TONE_INSTRUCTIONS = MessageTranslations::OpenaiSettings::DEFAULT_REPLY_TONE_INSTRUCTIONS

  class << self
    def hook_for(account)
      account.hooks.find_by(app_id: 'onyx_mcp', status: 'enabled')
    end

    def result_limit(hook)
      value = hook&.settings&.dig('result_limit').presence
      return DEFAULT_RESULT_LIMIT if value.blank?

      value.to_i.clamp(1, 20)
    end

    def source_types(hook)
      hook&.settings&.dig('source_types').to_s
          .split(',')
          .map(&:strip)
          .reject(&:blank?)
    end

    def query_for(hook, conversation_context)
      template = hook&.settings&.dig('query_template').presence || DEFAULT_QUERY_TEMPLATE
      return template.gsub('{{conversation_context}}', conversation_context) if template.include?('{{conversation_context}}')

      [template, conversation_context].join("\n\n")
    end

    def answer_guardrails(hook)
      hook&.settings&.dig('answer_guardrails').presence || DEFAULT_ANSWER_GUARDRAILS
    end

    def reply_tone_instructions(hook)
      hook&.settings&.dig('reply_tone_instructions').presence || DEFAULT_REPLY_TONE_INSTRUCTIONS
    end
  end
end
