class MessageTranslations::AutoTranslateJob < ApplicationJob
  queue_as :medium

  def perform(message_id, target_locale)
    message = Message.find(message_id)
    MessageTranslations::TranslateMessageService.new(message: message, target_locale: target_locale).perform
  rescue StandardError => e
    Rails.logger.error("[message-translation] #{e.class}: #{e.message}")
  end
end
