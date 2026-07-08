class CustomerIdentity::MessageEmailSuggestionService
  SUGGESTION_KEY = 'customer_identity_suggestion'.freeze
  ALLOWED_CHANNEL_TYPES = %w[
    Channel::FacebookPage
    Channel::Instagram
    Channel::Sms
    Channel::Telegram
    Channel::TwilioSms
    Channel::Whatsapp
  ].freeze

  pattr_initialize [:message!]

  def perform
    return unless eligible_message?

    matching_contact = find_matching_contact
    return if matching_contact.blank?

    store_suggestion(matching_contact)
  end

  private

  def eligible_message?
    message.incoming? &&
      !message.private? &&
      message.content.present? &&
      allowed_channel? &&
      current_contact.present? &&
      current_contact_unidentified? &&
      !existing_suggestion_blocks_message?
  end

  def allowed_channel?
    ALLOWED_CHANNEL_TYPES.include?(message.inbox.channel_type)
  end

  def current_contact
    @current_contact ||= message.conversation.contact
  end

  def current_contact_unidentified?
    current_contact.identifier.blank? && current_contact.email.blank?
  end

  def extracted_emails
    @extracted_emails ||= CustomerIdentity::EmailExtractor.new(content: message.content).perform
  end

  def find_matching_contact
    return if extracted_emails.blank?

    matching_contacts = message.account.contacts.where(email: extracted_emails)
                               .where.not(id: current_contact.id)
    contacts_by_email = matching_contacts.index_by { |contact| contact.email.downcase }

    extracted_emails.filter_map { |email| contacts_by_email[email] }
                    .find { |contact| safe_contact_match?(contact) }
  end

  def safe_contact_match?(contact)
    email_does_not_belong_to_current_contact?(contact) &&
      !phone_conflict?(contact)
  end

  def email_does_not_belong_to_current_contact?(contact)
    current_contact.email.blank? || current_contact.email.downcase != contact.email&.downcase
  end

  def phone_conflict?(contact)
    current_contact.phone_number.present? &&
      contact.phone_number.present? &&
      current_contact.phone_number != contact.phone_number
  end

  def existing_suggestion
    @existing_suggestion ||= begin
      suggestion = message.conversation.additional_attributes&.dig(SUGGESTION_KEY)
      suggestion if suggestion.is_a?(Hash)
    end
  end

  def existing_suggestion_blocks_message?
    return false if existing_suggestion.blank?
    return true if existing_suggestion['status'] == 'pending'
    return true if existing_suggestion['status'] == 'linked'

    dismissed_same_email_or_message?
  end

  def dismissed_same_email_or_message?
    return false unless existing_suggestion['status'] == 'dismissed'

    existing_suggestion['source_message_id'] == message.id ||
      extracted_emails.include?(existing_suggestion['email'].to_s.downcase)
  end

  def store_suggestion(contact)
    suggestion = {
      'status' => 'pending',
      'email' => contact.email,
      'matched_contact_id' => contact.id,
      'matched_contact_name' => contact.name,
      'source_message_id' => message.id,
      'detected_at' => Time.current.iso8601
    }

    additional_attributes = message.conversation.additional_attributes.merge(SUGGESTION_KEY => suggestion)
    message.conversation.update!(additional_attributes: additional_attributes)
  end
end
