require 'rails_helper'

RSpec.describe 'Conversation Reply Preparations API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/prepare_reply" }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  it 'stores the operator draft as the generation source' do
    expect do
      post url, params: { content: 'my rough draft' }, headers: agent.create_new_auth_token, as: :json
    end.to have_enqueued_job(AiGenerations::PreparedReplyJob)

    expect(response).to have_http_status(:accepted)
    expect(AiGenerations::PreparedReply.find_by(conversation: conversation, user: agent).source_content).to eq('my rough draft')
  end

  it 'replaces the source draft on a repeated request' do
    generation = create(:ai_generation_prepared_reply, account: account, conversation: conversation, user: agent, source_content: 'first draft')
    generation.complete!('prepared first draft')

    post url, params: { content: 'second draft' }, headers: agent.create_new_auth_token, as: :json

    expect(generation.reload.source_content).to eq('second draft')
    expect(generation).to be_pending
  end
end
