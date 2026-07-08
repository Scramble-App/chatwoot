class CustomerIdentity::ContactLinkService
  class Error < StandardError; end

  SUGGESTION_KEY = CustomerIdentity::MessageEmailSuggestionService::SUGGESTION_KEY

  pattr_initialize [:conversation!, :user]

  def perform
    validate!
    merge_contact!
    mark_linked!
  end

  private

  def validate!
    raise Error, 'Customer identity suggestion is not pending' unless pending_suggestion?
    raise Error, 'Matched contact was not found' if matched_contact.blank?
    raise Error, 'Current contact is already linked' unless current_contact_unidentified?
    raise Error, 'Matched contact is already attached to this conversation' if matched_contact.id == current_contact.id
    raise Error, 'Matched email belongs to the current contact' if matched_email_belongs_to_current_contact?
    raise Error, 'Phone number differs from the matched contact' if phone_conflict?
  end

  def current_contact
    @current_contact ||= conversation.contact
  end

  def current_contact_unidentified?
    current_contact.identifier.blank? && current_contact.email.blank?
  end

  def suggestion
    @suggestion ||= begin
      suggestion = conversation.additional_attributes&.dig(SUGGESTION_KEY)
      suggestion.is_a?(Hash) ? suggestion : {}
    end
  end

  def pending_suggestion?
    suggestion['status'] == 'pending'
  end

  def matched_contact
    @matched_contact ||= conversation.account.contacts.find_by(id: suggestion['matched_contact_id'])
  end

  def matched_email_belongs_to_current_contact?
    current_contact.email.present? && current_contact.email.downcase == suggestion['email'].to_s.downcase
  end

  def phone_conflict?
    current_contact.phone_number.present? &&
      matched_contact.phone_number.present? &&
      current_contact.phone_number != matched_contact.phone_number
  end

  def merge_contact!
    ContactMergeAction.new(
      account: conversation.account,
      base_contact: matched_contact,
      mergee_contact: current_contact
    ).perform
  end

  def mark_linked!
    conversation.reload

    updated_suggestion = suggestion.merge(
      'status' => 'linked',
      'linked_at' => Time.current.iso8601,
      'linked_by_user_id' => user&.id
    )

    conversation.update!(
      additional_attributes: conversation.additional_attributes.merge(SUGGESTION_KEY => updated_suggestion)
    )
    conversation
  end
end
