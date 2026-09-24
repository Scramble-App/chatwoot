require 'rails_helper'

RSpec.describe Internal::RemoveStaleAiGenerationsJob do
  it 'removes generations older than the retention window across all kinds' do
    old_summary = create(:ai_generation_summary)
    old_answer = create(:ai_generation_knowledge_answer)
    old_reply = create(:ai_generation_prepared_reply)
    [old_summary, old_answer, old_reply].each do |generation|
      generation.update!(updated_at: (described_class::RETENTION + 1.day).ago)
    end

    described_class.perform_now

    expect(AiGenerations::Summary.where(id: old_summary.id)).to be_empty
    expect(AiGenerations::KnowledgeAnswer.where(id: old_answer.id)).to be_empty
    expect(AiGenerations::PreparedReply.where(id: old_reply.id)).to be_empty
  end

  it 'keeps recent generations' do
    fresh = create(:ai_generation_summary)

    described_class.perform_now

    expect(AiGenerations::Summary.find(fresh.id)).to be_present
  end

  it 'runs on the housekeeping queue' do
    expect(described_class.new.queue_name).to eq('housekeeping')
  end
end
