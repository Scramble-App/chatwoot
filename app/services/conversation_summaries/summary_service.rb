class ConversationSummaries::SummaryService
  class Error < StandardError; end

  CUSTOMER_CONTEXT_MESSAGE_LIMIT = 10
  CONVERSATION_CONTEXT_CHARACTER_LIMIT = 40_000

  pattr_initialize [:conversation!, :user!]

  def perform
    hook = MessageTranslations::OpenaiSettings.hook_for(conversation.account)
    raise Error, 'OpenAI integration is not configured' if hook.blank?

    context = conversation_context_text
    raise Error, 'No conversation messages available to summarize' if context.blank?

    ConversationSummaries::OpenaiSummaryService.new(
      hook: hook,
      conversation_context: context,
      output_language: output_language_label
    ).perform
  end

  private

  def conversation_context_text
    selected = []
    character_count = 0

    messages_for_context.each do |message|
      formatted = format_message(message)
      next if formatted.blank?
      break if character_count + formatted.length > CONVERSATION_CONTEXT_CHARACTER_LIMIT

      selected << formatted
      character_count += formatted.length
    end

    selected.join("\n")
  end

  def messages_for_context
    first_customer_message = latest_customer_messages.first
    return Message.none if first_customer_message.blank?

    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .where('created_at > :created_at OR (created_at = :created_at AND id >= :id)',
                       created_at: first_customer_message.created_at,
                       id: first_customer_message.id)
                .where(
                  '(messages.message_type = :incoming AND messages.private = :public_message) OR messages.message_type = :outgoing',
                  incoming: Message.message_types[:incoming],
                  outgoing: Message.message_types[:outgoing],
                  public_message: false
                )
                .reorder(created_at: :asc, id: :asc)
  end

  def latest_customer_messages
    conversation.messages
                .incoming
                .where(private: false)
                .reorder(created_at: :desc, id: :desc)
                .limit(CUSTOMER_CONTEXT_MESSAGE_LIMIT)
                .reverse
  end

  def format_message(message)
    content = MessageTranslations::OpenaiTranslationService.source_text_for(message)
    return if content.blank?

    speaker = message_speaker(message)
    "#{speaker}: #{content}"
  end

  def message_speaker(message)
    return 'Customer' if message.incoming?
    return 'Internal private note' if message.private?

    'Agent reply to customer'
  end

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
