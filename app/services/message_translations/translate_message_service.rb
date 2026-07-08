class MessageTranslations::TranslateMessageService
  pattr_initialize [:message!, :target_locale!]

  def perform
    return unless translatable?

    hook = MessageTranslations::OpenaiSettings.hook_for(message.account)
    return unless MessageTranslations::OpenaiSettings.translation_enabled?(hook)

    translate_with_hook(hook)
  end

  private

  def translate_with_hook(hook)
    translation = find_or_create_translation
    return translation if translation.completed?

    translation.update!(status: :pending, error_message: nil)
    content = MessageTranslations::OpenaiTranslationService.new(
      hook: hook,
      message: message,
      target_locale: target_locale
    ).perform

    translation.update!(
      status: :completed,
      content: content,
      error_message: nil,
      model: MessageTranslations::OpenaiSettings.model(hook)
    )
    MessageTranslations::BroadcastService.new(translation: translation).perform
    translation
  rescue StandardError => e
    translation&.update(status: :failed, error_message: e.message)
    raise e
  end

  def find_or_create_translation
    MessageTranslation.find_or_create_by!(
      account: message.account,
      message: message,
      target_locale: target_locale,
      provider: MessageTranslation::PROVIDER_OPENAI
    )
  end

  def translatable?
    target_locale.present? &&
      message.incoming? &&
      !message.private? &&
      MessageTranslations::OpenaiTranslationService.source_text_for(message).present?
  end
end
