require 'rails_helper'

RSpec.describe AgentBotKnowledgeQuestion do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot) }
    it { is_expected.to belong_to(:knowledge_entry).class_name('AgentBotKnowledgeEntry') }
    it { is_expected.to belong_to(:conversation) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_length_of(:content).is_at_most(2_000) }

    it 'takes the bot and the account from the entry when blank' do
      entry = create(:agent_bot_knowledge_entry, status: :needs_answer)
      conversation = create(:conversation, account: entry.account)

      question = entry.questions.create!(conversation: conversation, content: 'Is this a sample question?')

      expect(question.agent_bot).to eq(entry.agent_bot)
      expect(question.account).to eq(entry.account)
    end
  end

  it 'is deleted with its conversation' do
    question = create(:agent_bot_knowledge_question)

    question.conversation.destroy!

    expect(described_class.exists?(question.id)).to be(false)
    expect(AgentBotKnowledgeEntry.exists?(question.knowledge_entry_id)).to be(true)
  end
end
