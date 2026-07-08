class ReplyPreparations::PrepareReplyService
  class Error < StandardError; end

  CUSTOMER_CONTEXT_MESSAGE_LIMIT = 5

  pattr_initialize [:conversation!, :content!]

  def perform
    raise Error, 'Reply content is required' if operator_draft.blank?

    hook = MessageTranslations::OpenaiSettings.hook_for(conversation.account)
    raise Error, 'OpenAI integration is not configured' if hook.blank?

    customer_context = customer_context_text
    raise Error, 'No incoming customer messages available for language detection' if customer_context.blank?

    ReplyPreparations::OpenaiPrepareReplyService.new(
      hook: hook,
      content: content,
      customer_context: customer_context
    ).perform
  end

  private

  def operator_draft
    content.to_s.strip
  end

  def customer_context_text
    messages = conversation.messages
                           .incoming
                           .where(private: false)
                           .order(created_at: :desc)
                           .limit(CUSTOMER_CONTEXT_MESSAGE_LIMIT)
                           .to_a
                           .sort_by(&:created_at)

    messages.filter_map do |message|
      MessageTranslations::OpenaiTranslationService.source_text_for(message).presence
    end.join("\n\n---\n\n")
  end
end
