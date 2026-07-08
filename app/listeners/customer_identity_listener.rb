class CustomerIdentityListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)

    CustomerIdentity::MessageEmailSuggestionJob.perform_later(message.id)
  end
end
