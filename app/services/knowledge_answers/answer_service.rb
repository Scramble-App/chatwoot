class KnowledgeAnswers::AnswerService
  class Error < StandardError; end

  CONVERSATION_CONTEXT_MESSAGE_LIMIT = 20
  CONVERSATION_CONTEXT_CHARACTER_LIMIT = 30_000
  KNOWLEDGE_CONTEXT_CHARACTER_LIMIT = 30_000

  pattr_initialize [:conversation!, :user!]

  # rubocop:disable Metrics/MethodLength
  def perform
    openai_hook = MessageTranslations::OpenaiSettings.hook_for(conversation.account)
    raise Error, 'OpenAI integration is not configured' if openai_hook.blank?

    onyx_hook = KnowledgeAnswers::OnyxSettings.hook_for(conversation.account)
    raise Error, 'Onyx MCP integration is not configured' if onyx_hook.blank?

    context = conversation_context_text
    raise Error, 'No public conversation messages available for knowledge answer' if context.blank?

    onyx_result = Integrations::OnyxMcp::Client.new(hook: onyx_hook).search_indexed_documents(
      query: KnowledgeAnswers::OnyxSettings.query_for(onyx_hook, context),
      source_types: KnowledgeAnswers::OnyxSettings.source_types(onyx_hook),
      limit: KnowledgeAnswers::OnyxSettings.result_limit(onyx_hook)
    )

    knowledge_context = knowledge_context_text(onyx_result, KnowledgeAnswers::OnyxSettings.result_limit(onyx_hook))
    raise Error, 'No knowledge base results found in Onyx' if knowledge_context.blank?

    KnowledgeAnswers::OpenaiAnswerService.new(
      openai_hook: openai_hook,
      onyx_hook: onyx_hook,
      conversation_context: context,
      knowledge_context: knowledge_context,
      output_language: output_language_label
    ).perform
  end
  # rubocop:enable Metrics/MethodLength

  private

  def conversation_context_text
    selected = []
    character_count = 0

    public_messages_for_context.each do |message|
      formatted = format_message(message)
      next if formatted.blank?
      break if character_count + formatted.length > CONVERSATION_CONTEXT_CHARACTER_LIMIT

      selected << formatted
      character_count += formatted.length
    end

    selected.join("\n")
  end

  def public_messages_for_context
    conversation.messages
                .where(message_type: [:incoming, :outgoing], private: false)
                .reorder(created_at: :desc, id: :desc)
                .limit(CONVERSATION_CONTEXT_MESSAGE_LIMIT)
                .to_a
                .reverse
  end

  def format_message(message)
    content = MessageTranslations::OpenaiTranslationService.source_text_for(message)
    return if content.blank?

    "#{message_speaker(message)}: #{content}"
  end

  def message_speaker(message)
    message.incoming? ? 'Customer' : 'Agent reply to customer'
  end

  def knowledge_context_text(onyx_result, result_limit)
    selected = []
    character_count = 0

    documents_from(onyx_result).first(result_limit).each_with_index do |document, index|
      formatted = format_document(document, index + 1)
      next if formatted.blank?
      break if character_count + formatted.length > KNOWLEDGE_CONTEXT_CHARACTER_LIMIT

      selected << formatted
      character_count += formatted.length
    end

    selected.join("\n\n")
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
  def documents_from(onyx_result)
    direct_documents = onyx_result&.dig('documents')
    return direct_documents if direct_documents.present?

    direct_results = onyx_result&.dig('results')
    return direct_results if direct_results.present?

    structured_documents = onyx_result&.dig('structuredContent', 'documents')
    return structured_documents if structured_documents.present?

    structured_results = onyx_result&.dig('structuredContent', 'results')
    return structured_results if structured_results.present?

    content_items = onyx_result&.dig('content')
    Array(content_items).flat_map do |item|
      next [] unless item['type'] == 'text' && item['text'].present?

      parsed = JSON.parse(item['text'])
      parsed['documents'].presence || parsed['results'] || []
    rescue JSON::ParserError
      []
    end
  end

  def format_document(document, index)
    doc = document.to_h.with_indifferent_access
    content = doc[:content].presence || doc[:snippet].presence || doc[:text].presence
    return if content.blank?

    [
      "Knowledge result #{index}:",
      ("Title: #{doc[:semantic_identifier].presence || doc[:title]}" if doc[:semantic_identifier].present? || doc[:title].present?),
      ("Source: #{doc[:source_type]}" if doc[:source_type].present?),
      ("URL: #{doc[:link].presence || doc[:url]}" if doc[:link].present? || doc[:url].present?),
      "Content: #{content}"
    ].compact.join("\n")
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

  def output_language_label
    language_label_for(operator_locale) || language_label_for(conversation.account.locale) || conversation.account.locale_english_name
  end

  def language_label_for(locale)
    locale_code = locale.to_s.split(/[-_]/).first
    return if locale_code.blank?

    language_name = ISO_639.find(locale_code)&.english_name || locale_code
    "#{language_name} (#{locale_code})"
  end

  def operator_locale
    account_user&.translation_locale
  end

  def account_user
    @account_user ||= conversation.account.account_users.find_by(user: user)
  end
end
