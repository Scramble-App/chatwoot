require 'rails_helper'

RSpec.describe 'Conversation Developer Reports API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/developer_report" }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  it 'queues a developer report for the operator without creating a message' do
    expect do
      post url, headers: agent.create_new_auth_token, as: :json
    end.to have_enqueued_job(AiGenerations::DeveloperReportJob).and not_change(Message, :count)

    expect(response).to have_http_status(:accepted)
    expect(AiGenerations::DeveloperReport.find_by(conversation: conversation, user: agent)).to be_pending
  end

  it 'returns unauthorized for an agent outside the inbox' do
    outsider = create(:user, account: account, role: :agent)

    post url, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(AiGenerations::DeveloperReportJob).not_to have_been_enqueued
  end
end
