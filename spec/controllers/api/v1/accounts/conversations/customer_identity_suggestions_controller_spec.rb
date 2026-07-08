require 'rails_helper'

RSpec.describe 'Customer identity suggestions API', type: :request do
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

  describe 'POST /link' do
    it 'returns unauthorized for unauthenticated users' do
      post link_path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized when the agent cannot access the conversation inbox' do
      post link_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'links the conversation contact for an agent with inbox access' do
      create(:inbox_member, inbox: inbox, user: agent)

      post link_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.contact).to eq(matched_contact)
      expect(response.parsed_body.dig('meta', 'sender', 'id')).to eq(matched_contact.id)
      expect(response.parsed_body.dig('additional_attributes', 'customer_identity_suggestion', 'status')).to eq('linked')
    end
  end

  describe 'POST /dismiss' do
    it 'dismisses the suggestion for an agent with inbox access' do
      create(:inbox_member, inbox: inbox, user: agent)

      post dismiss_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('additional_attributes', 'customer_identity_suggestion', 'status')).to eq('dismissed')
      expect(conversation.reload.additional_attributes.dig('customer_identity_suggestion', 'dismissed_by_user_id')).to eq(agent.id)
    end
  end

  def link_path
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/customer_identity_suggestion/link"
  end

  def dismiss_path
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/customer_identity_suggestion/dismiss"
  end
end
