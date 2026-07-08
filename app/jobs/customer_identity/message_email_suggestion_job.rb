class CustomerIdentity::MessageEmailSuggestionJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find(message_id)
    CustomerIdentity::MessageEmailSuggestionService.new(message: message).perform
  rescue StandardError => e
    Rails.logger.error("[customer-identity] #{e.class}: #{e.message}")
  end
end
