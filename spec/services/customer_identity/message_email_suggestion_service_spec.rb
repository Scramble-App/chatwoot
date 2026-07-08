require 'rails_helper'

RSpec.describe CustomerIdentity::MessageEmailSuggestionService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_telegram, account: account) }
  let(:inbox) { channel.inbox }
  let(:current_contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: current_contact, inbox: inbox) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: current_contact,
      contact_inbox: contact_inbox
    )
  end
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: current_contact,
      content: message_content
    )
  end
  let(:message_content) { 'My email is customer@example.com' }

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  it 'creates a pending suggestion for an eligible social channel incoming message' do
    matched_contact = create(:contact, account: account, email: 'customer@example.com', name: 'CRM User', identifier: 'crm-1')

    described_class.new(message: message).perform

    suggestion = conversation.reload.additional_attributes['customer_identity_suggestion']
    expect(suggestion).to include(
      'status' => 'pending',
      'email' => 'customer@example.com',
      'matched_contact_id' => matched_contact.id,
      'matched_contact_name' => 'CRM User',
      'source_message_id' => message.id
    )
  end

  it 'uses the first exact email match when multiple emails are present' do
    first_contact = create(:contact, account: account, email: 'first@example.com')
    create(:contact, account: account, email: 'second@example.com')
    message.update!(content: 'Try first@example.com or second@example.com')

    described_class.new(message: message).perform

    suggestion = conversation.reload.additional_attributes['customer_identity_suggestion']
    expect(suggestion['matched_contact_id']).to eq(first_contact.id)
    expect(suggestion['email']).to eq('first@example.com')
  end

  it 'does not create a suggestion without an exact contact email match' do
    create(:contact, account: account, email: 'other@example.com')

    described_class.new(message: message).perform

    expect(conversation.reload.additional_attributes['customer_identity_suggestion']).to be_nil
  end

  it 'does not create a suggestion for the email channel' do
    email_channel = create(:channel_email, account: account)
    email_inbox = email_channel.inbox
    email_contact_inbox = create(:contact_inbox, contact: current_contact, inbox: email_inbox)
    email_conversation = create(
      :conversation,
      account: account,
      inbox: email_inbox,
      contact: current_contact,
      contact_inbox: email_contact_inbox
    )
    email_message = create(
      :message,
      account: account,
      inbox: email_inbox,
      conversation: email_conversation,
      sender: current_contact,
      content: message_content
    )
    create(:contact, account: account, email: 'customer@example.com')

    described_class.new(message: email_message).perform

    expect(email_conversation.reload.additional_attributes['customer_identity_suggestion']).to be_nil
  end

  it 'does not create a suggestion when current contact already has an identifier' do
    current_contact.update!(identifier: 'telegram-user')
    create(:contact, account: account, email: 'customer@example.com')

    described_class.new(message: message).perform

    expect(conversation.reload.additional_attributes['customer_identity_suggestion']).to be_nil
  end

  it 'does not create a suggestion when current contact already has an email' do
    current_contact.update!(email: 'current@example.com')
    create(:contact, account: account, email: 'customer@example.com')

    described_class.new(message: message).perform

    expect(conversation.reload.additional_attributes['customer_identity_suggestion']).to be_nil
  end

  it 'does not create a suggestion when phone numbers conflict' do
    current_contact.update!(phone_number: '+15550101010')
    create(:contact, account: account, email: 'customer@example.com', phone_number: '+15550101011')

    described_class.new(message: message).perform

    expect(conversation.reload.additional_attributes['customer_identity_suggestion']).to be_nil
  end

  it 'does not recreate a dismissed suggestion for the same email' do
    create(:contact, account: account, email: 'customer@example.com')
    conversation.update!(
      additional_attributes: {
        'customer_identity_suggestion' => {
          'status' => 'dismissed',
          'email' => 'customer@example.com',
          'source_message_id' => 123
        }
      }
    )

    described_class.new(message: message).perform

    suggestion = conversation.reload.additional_attributes['customer_identity_suggestion']
    expect(suggestion['status']).to eq('dismissed')
    expect(suggestion['source_message_id']).to eq(123)
  end
end
