require 'rails_helper'

RSpec.describe AiGenerations::BaseJob do
  let(:generation) { create(:ai_generation_knowledge_answer) }
  let(:answer_service) { instance_double(KnowledgeAnswers::AnswerService) }

  before do
    allow(KnowledgeAnswers::AnswerService).to receive(:new).and_return(answer_service)
  end

  describe 'a successful run' do
    before do
      allow(answer_service).to receive(:perform).and_return('answer from onyx')
    end

    it 'stores the generated content' do
      AiGenerations::KnowledgeAnswerJob.perform_now(generation.id)

      expect(generation.reload).to be_completed
      expect(generation.content).to eq('answer from onyx')
    end

    it 'calls the existing service with the conversation and user' do
      AiGenerations::KnowledgeAnswerJob.perform_now(generation.id)

      expect(KnowledgeAnswers::AnswerService).to have_received(:new).with(
        conversation: generation.conversation,
        user: generation.user
      )
    end

    it 'broadcasts the running and completed transitions' do
      expect(AiGenerations::BroadcastService).to receive(:new).twice.and_call_original

      AiGenerations::KnowledgeAnswerJob.perform_now(generation.id)
    end
  end

  describe 'an expected service failure' do
    before do
      allow(answer_service).to receive(:perform).and_raise(KnowledgeAnswers::AnswerService::Error, 'No knowledge base results found in Onyx')
    end

    it 'records the failure without re-raising' do
      expect { AiGenerations::KnowledgeAnswerJob.perform_now(generation.id) }.not_to raise_error

      expect(generation.reload).to be_failed
      expect(generation.error_message).to eq('No knowledge base results found in Onyx')
    end

    it 'still broadcasts so the dashboard stops spinning' do
      expect(AiGenerations::BroadcastService).to receive(:new).twice.and_call_original

      AiGenerations::KnowledgeAnswerJob.perform_now(generation.id)
    end
  end

  describe 'an unexpected failure' do
    before do
      allow(answer_service).to receive(:perform).and_raise(StandardError, 'PG::ConnectionBad: could not connect')
    end

    it 'hides the internal detail behind a generic message' do
      expect { AiGenerations::KnowledgeAnswerJob.perform_now(generation.id) }.not_to raise_error

      expect(generation.reload).to be_failed
      expect(generation.error_message).to eq(I18n.t('ai_generations.generic_error'))
    end
  end

  describe 'a deleted generation' do
    it 'does nothing when the record is gone' do
      generation_id = generation.id
      generation.destroy!

      expect { AiGenerations::KnowledgeAnswerJob.perform_now(generation_id) }.not_to raise_error
      expect(KnowledgeAnswers::AnswerService).not_to have_received(:new)
    end
  end

  describe 'queue' do
    it 'runs on the high queue so operators are not stuck behind background work' do
      expect(AiGenerations::KnowledgeAnswerJob.new.queue_name).to eq('high')
    end
  end
end
