require 'rails_helper'

RSpec.describe CustomerIdentity::ContactLinkService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_telegram, account: account) }
  let(:inbox) { channel.inbox }
  let(:current_contact) { create(:contact, account: account) }
  let(:matched_contact) { create(:contact, account: account, email: 'customer@example.com', identifier: 'crm-1') }
  let(:contact_inbox) { create(:contact_inbox, contact: current_contact, inbox: inbox, source_id: 'telegram-user-1') }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: current_contact,
      contact_inbox: contact_inbox,
      additional_attributes: {
        'customer_identity_suggestion' => {
          'status' => 'pending',
          'email' => matched_contact.email,
          'matched_contact_id' => matched_contact.id,
          'matched_contact_name' => matched_contact.name,
          'source_message_id' => 1
        }
      }
    )
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  it 'merges the current contact into the matched CRM contact and preserves the channel source id' do
    described_class.new(conversation: conversation, user: agent).perform

    expect(conversation.reload.contact).to eq(matched_contact)
    expect(contact_inbox.reload.contact).to eq(matched_contact)
    expect(contact_inbox.source_id).to eq('telegram-user-1')
    expect(Contact.exists?(current_contact.id)).to be(false)

    suggestion = conversation.additional_attributes['customer_identity_suggestion']
    expect(suggestion['status']).to eq('linked')
    expect(suggestion['linked_by_user_id']).to eq(agent.id)
  end

  it 'rejects linking when current contact already has an email' do
    current_contact.update!(email: 'current@example.com')

    expect { described_class.new(conversation: conversation, user: agent).perform }
      .to raise_error(described_class::Error, 'Current contact is already linked')
  end

  it 'rejects linking when phone numbers conflict' do
    current_contact.update!(phone_number: '+15550101010')
    matched_contact.update!(phone_number: '+15550101011')

    expect { described_class.new(conversation: conversation, user: agent).perform }
      .to raise_error(described_class::Error, 'Phone number differs from the matched contact')
  end

  it 'rejects linking when the suggestion is not pending' do
    conversation.update!(
      additional_attributes: {
        'customer_identity_suggestion' => conversation.additional_attributes['customer_identity_suggestion'].merge('status' => 'dismissed')
      }
    )

    expect { described_class.new(conversation: conversation, user: agent).perform }
      .to raise_error(described_class::Error, 'Customer identity suggestion is not pending')
  end
end
