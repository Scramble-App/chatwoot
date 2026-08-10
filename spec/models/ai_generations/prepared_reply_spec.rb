require 'rails_helper'

RSpec.describe AiGenerations::PreparedReply do
  it 'shares the generation lifecycle' do
    generation = create(:ai_generation_prepared_reply)

    generation.complete!('prepared text')

    expect(generation.reload).to be_completed
    expect(generation.push_event_data[:content]).to eq('prepared text')
  end

  it 'stores the operator draft it started from' do
    generation = create(:ai_generation_prepared_reply, source_content: 'my rough draft')

    expect(generation.reload.source_content).to eq('my rough draft')
  end

  it 'keeps knowledge answers in a separate table' do
    answer = create(:ai_generation_knowledge_answer)

    expect(described_class.where(id: answer.id)).to be_empty
    expect(AiGenerations::KnowledgeAnswer.find(answer.id)).to be_present
  end
end
