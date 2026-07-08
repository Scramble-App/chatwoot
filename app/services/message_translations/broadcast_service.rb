class MessageTranslations::BroadcastService
  include Events::Types

  pattr_initialize [:translation!]

  def perform
    return unless translation.completed?

    tokens = recipient_tokens
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, MESSAGE_TRANSLATION_UPDATED, payload)
  end

  private

  def message
    @message ||= translation.message
  end

  def account
    @account ||= translation.account
  end

  def payload
    {
      account_id: account.id,
      conversation_id: message.conversation.display_id,
      message_id: message.id,
      operator_translation: translation.push_event_data
    }
  end

  def recipient_tokens
    user_ids = (message.conversation.inbox.members.ids + account.administrators.ids).uniq
    account.account_users
           .includes(:user)
           .where(user_id: user_ids, translation_locale: translation.target_locale)
           .filter_map { |account_user| account_user.user&.pubsub_token }
           .uniq
  end
end
