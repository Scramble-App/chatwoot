require 'rails_helper'

RSpec.describe 'Conversation Knowledge Answers API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/knowledge_answer" }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  describe 'POST' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post url, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'accepts the request, enqueues the job and returns the pending generation' do
      expect do
        post url, headers: agent.create_new_auth_token, as: :json
      end.to have_enqueued_job(AiGenerations::KnowledgeAnswerJob)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['status']).to eq('pending')
      expect(AiGenerations::KnowledgeAnswer.find_by(conversation: conversation, user: agent)).to be_present
    end

    it 'does not enqueue a second job while a generation is in progress' do
      post url, headers: agent.create_new_auth_token, as: :json

      expect do
        post url, headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(AiGenerations::KnowledgeAnswerJob)

      expect(response).to have_http_status(:accepted)
      expect(AiGenerations::KnowledgeAnswer.where(conversation: conversation, user: agent).count).to eq(1)
    end

    it 'enqueues again when the in-progress generation went stale' do
      generation = create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: agent)
      generation.mark_running!
      generation.update!(updated_at: (AiGeneratable::STALE_TIMEOUT + 1.minute).ago)

      expect do
        post url, headers: agent.create_new_auth_token, as: :json
      end.to have_enqueued_job(AiGenerations::KnowledgeAnswerJob)

      expect(generation.reload).to be_pending
    end

    it 'clears the previous result when starting a new generation' do
      generation = create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: agent)
      generation.complete!('old answer')

      post url, headers: agent.create_new_auth_token, as: :json

      expect(generation.reload).to be_pending
      expect(generation.content).to be_nil
    end
  end

  describe 'GET' do
    it 'returns no content when nothing was generated' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end

    it 'returns the stored generation' do
      generation = create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: agent)
      generation.complete!('answer text')

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['content']).to eq('answer text')
      expect(response.parsed_body['status']).to eq('completed')
    end

    it 'does not expose another operator generation' do
      other_agent = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: conversation.inbox, user: other_agent)
      create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: other_agent).complete!('not yours')

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'DELETE' do
    it 'removes the generation so a dismissed suggestion stays dismissed' do
      generation = create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: agent)

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(AiGenerations::KnowledgeAnswer.where(id: generation.id)).to be_empty
    end

    it 'does not delete another operator generation' do
      other_agent = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: conversation.inbox, user: other_agent)
      generation = create(:ai_generation_knowledge_answer, account: account, conversation: conversation, user: other_agent)

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(AiGenerations::KnowledgeAnswer.find(generation.id)).to be_present
    end
  end
end
