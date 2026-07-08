class MessageTranslationListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless eligible_message?(message)

    hook = MessageTranslations::OpenaiSettings.hook_for(account)
    return unless MessageTranslations::OpenaiSettings.translation_enabled?(hook)
    return unless MessageTranslations::OpenaiSettings.auto_translate_incoming?(hook)

    target_locales_for(message, account).each do |target_locale|
      MessageTranslations::AutoTranslateJob.perform_later(message.id, target_locale)
    end
  end

  private

  def eligible_message?(message)
    message.incoming? &&
      !message.private? &&
      MessageTranslations::OpenaiTranslationService.source_text_for(message).present?
  end

  def target_locales_for(message, account)
    user_ids = (message.conversation.inbox.members.ids + account.administrators.ids).uniq
    account.account_users
           .where(user_id: user_ids)
           .where.not(translation_locale: nil)
           .where.not(translation_locale: '')
           .distinct
           .pluck(:translation_locale)
  end
end
