require 'rails_helper'

RSpec.describe AiGeneratable do
  subject(:generation) { create(:ai_generation_summary) }

  describe 'status transitions' do
    it 'starts as pending and counts as in progress' do
      expect(generation).to be_pending
      expect(generation).to be_in_progress
    end

    it 'moves to running' do
      generation.mark_running!

      expect(generation.reload).to be_running
      expect(generation).to be_in_progress
    end

    it 'stores content on completion and clears the previous error' do
      generation.fail!('boom')
      generation.complete!('generated text')

      expect(generation.reload).to be_completed
      expect(generation.content).to eq('generated text')
      expect(generation.error_message).to be_nil
    end

    it 'stores the message on failure' do
      generation.fail!('Onyx MCP is not configured')

      expect(generation.reload).to be_failed
      expect(generation.error_message).to eq('Onyx MCP is not configured')
      expect(generation).not_to be_in_progress
    end

    it 'resets to pending for a retry and clears previous output' do
      generation.complete!('old text')
      generation.reset_for_retry!

      expect(generation.reload).to be_pending
      expect(generation.content).to be_nil
      expect(generation.error_message).to be_nil
    end

    it 'applies extra attributes when resetting' do
      generation.reset_for_retry!(provider: 'openai')

      expect(generation.reload.provider).to eq('openai')
    end
  end

  describe '#stale?' do
    it 'is false for a fresh in-progress record' do
      generation.mark_running!

      expect(generation).not_to be_stale
    end

    it 'is true once an in-progress record is older than STALE_TIMEOUT' do
      generation.mark_running!
      generation.update!(updated_at: (AiGeneratable::STALE_TIMEOUT + 1.minute).ago)

      expect(generation).to be_stale
    end

    it 'is false for a completed record regardless of age' do
      generation.complete!('text')
      generation.update!(updated_at: 1.year.ago)

      expect(generation).not_to be_stale
    end
  end

  describe '#push_event_data' do
    it 'exposes the fields the dashboard consumes' do
      generation.complete!('generated text')

      expect(generation.push_event_data).to include(
        id: generation.id,
        status: 'completed',
        content: 'generated text',
        error_message: nil,
        provider: 'openai'
      )
      expect(generation.push_event_data[:updated_at]).to eq(generation.updated_at.to_i)
    end

    it 'reports a stale record as failed with a timeout message' do
      generation.mark_running!
      generation.update!(updated_at: (AiGeneratable::STALE_TIMEOUT + 1.minute).ago)

      expect(generation.push_event_data[:status]).to eq('failed')
      expect(generation.push_event_data[:error_message]).to eq(I18n.t('ai_generations.stale'))
    end
  end

  describe 'owner deletion' do
    let!(:summary) { create(:ai_generation_summary) }
    let!(:knowledge_answer) do
      create(:ai_generation_knowledge_answer, account: summary.account, conversation: summary.conversation, user: summary.user)
    end
    let!(:prepared_reply) do
      create(:ai_generation_prepared_reply, account: summary.account, conversation: summary.conversation, user: summary.user)
    end

    it 'lets the conversation be destroyed and takes the generations with it' do
      expect { summary.conversation.destroy! }.not_to raise_error

      expect(AiGenerations::Summary.exists?(summary.id)).to be(false)
      expect(AiGenerations::KnowledgeAnswer.exists?(knowledge_answer.id)).to be(false)
      expect(AiGenerations::PreparedReply.exists?(prepared_reply.id)).to be(false)
    end

    it 'lets the requesting user be destroyed and takes the generations with it' do
      expect { summary.user.destroy! }.not_to raise_error

      expect(AiGenerations::Summary.exists?(summary.id)).to be(false)
      expect(AiGenerations::KnowledgeAnswer.exists?(knowledge_answer.id)).to be(false)
      expect(AiGenerations::PreparedReply.exists?(prepared_reply.id)).to be(false)
    end

    it 'lets the account be destroyed' do
      expect { summary.account.destroy! }.not_to raise_error
    end
  end

  describe 'uniqueness' do
    it 'allows only one record per conversation and user' do
      duplicate = build(:ai_generation_summary, account: generation.account, conversation: generation.conversation, user: generation.user)

      expect(duplicate).not_to be_valid
    end
  end
end
