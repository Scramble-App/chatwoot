require 'rails_helper'

RSpec.describe AiGenerations::BroadcastService do
  let(:generation) { create(:ai_generation_knowledge_answer) }
  let(:event_name) { Events::Types::KNOWLEDGE_ANSWER_UPDATED }

  it 'broadcasts only to the requesting user' do
    generation.complete!('answer text')

    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      [generation.user.pubsub_token],
      event_name,
      hash_including(
        id: generation.id,
        status: 'completed',
        content: 'answer text',
        account_id: generation.account_id,
        conversation_id: generation.conversation.display_id
      )
    )

    described_class.new(generation: generation, event_name: event_name).perform
  end

  it 'broadcasts failures too' do
    generation.fail!('Onyx MCP is not configured')

    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      [generation.user.pubsub_token],
      event_name,
      hash_including(status: 'failed', error_message: 'Onyx MCP is not configured')
    )

    described_class.new(generation: generation, event_name: event_name).perform
  end
end
