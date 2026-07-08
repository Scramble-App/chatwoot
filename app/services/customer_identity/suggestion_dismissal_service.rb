class CustomerIdentity::SuggestionDismissalService
  class Error < StandardError; end

  SUGGESTION_KEY = CustomerIdentity::MessageEmailSuggestionService::SUGGESTION_KEY

  pattr_initialize [:conversation!, :user]

  def perform
    raise Error, 'Customer identity suggestion is not pending' unless pending_suggestion?

    updated_suggestion = suggestion.merge(
      'status' => 'dismissed',
      'dismissed_at' => Time.current.iso8601,
      'dismissed_by_user_id' => user&.id
    )

    conversation.update!(
      additional_attributes: conversation.additional_attributes.merge(SUGGESTION_KEY => updated_suggestion)
    )
    conversation
  end

  private

  def suggestion
    @suggestion ||= begin
      suggestion = conversation.additional_attributes&.dig(SUGGESTION_KEY)
      suggestion.is_a?(Hash) ? suggestion : {}
    end
  end

  def pending_suggestion?
    suggestion['status'] == 'pending'
  end
end
