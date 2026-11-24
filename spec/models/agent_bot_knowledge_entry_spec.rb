require 'rails_helper'

RSpec.describe AgentBotKnowledgeEntry do
  let(:agent_bot) { create(:agent_bot, :ai_agent) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot) }
    it { is_expected.to have_many(:questions).class_name('AgentBotKnowledgeQuestion').dependent(:delete_all) }
  end

  describe 'validations' do
    it { is_expected.to define_enum_for(:status).with_values(draft: 0, published: 1, needs_answer: 2) }
    it { is_expected.to validate_presence_of(:question) }
    it { is_expected.to validate_length_of(:question).is_at_most(2_000) }
    it { is_expected.to validate_length_of(:key).is_at_most(255) }
    it { is_expected.to validate_length_of(:category).is_at_most(255) }
    it { is_expected.to validate_length_of(:frequency).is_at_most(255) }
    it { is_expected.to validate_length_of(:alternative_questions).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:short_answer).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:answer).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:selling_point).is_at_most(10_000) }

    it 'starts as a draft that was never asked' do
      entry = described_class.new

      expect(entry).to be_draft
      expect(entry.asked_count).to eq(0)
    end

    it 'needs an answer or a short answer to be published' do
      entry = build(:agent_bot_knowledge_entry, agent_bot: agent_bot, answer: '', short_answer: nil)

      expect(entry).not_to be_valid
      expect(entry.errors.full_messages).to include('Answer or short answer is required to publish the entry')
    end

    it 'publishes an entry with only a short or only a detailed answer' do
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, answer: nil)).to be_valid
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, short_answer: nil)).to be_valid
    end

    it 'keeps drafts and unanswered questions without an answer' do
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :draft, answer: nil, short_answer: nil)).to be_valid
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer, answer: nil, short_answer: nil)).to be_valid
    end

    it 'takes the account from the bot when blank' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, account: nil)

      expect(entry.account).to eq(agent_bot.account)
    end
  end

  describe 'key' do
    def create_entry(key: nil)
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: key)
    end

    it 'starts the knowledge base of a bot at KB-001' do
      expect(create_entry.key).to eq('KB-001')
    end

    it 'takes the next number after the highest KB- key of the bot' do
      create_entry(key: 'KB-012')
      create_entry(key: 'KB-7')
      create_entry(key: 'FAQ-99')
      create_entry(key: 'KB-90a')
      create(:agent_bot_knowledge_entry, key: 'KB-500')

      expect(create_entry.key).to eq('KB-013')
    end

    it 'uses at least 3 digits and more when the numbers grow' do
      create_entry(key: 'KB-9')
      expect(create_entry.key).to eq('KB-010')

      create_entry(key: 'KB-999')
      expect(create_entry.key).to eq('KB-1000')
    end

    it 'assigns a key when the given one is blank' do
      create_entry(key: 'KB-004')

      expect(create_entry(key: '  ').key).to eq('KB-005')
    end

    it 'keeps a given key' do
      expect(create_entry(key: 'PRICING-1').key).to eq('PRICING-1')
    end

    it 'is unique per bot' do
      create_entry(key: 'KB-001')

      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001')).not_to be_valid
      expect(build(:agent_bot_knowledge_entry, key: 'KB-001')).to be_valid
    end
  end

  it 'deletes its customer questions with it' do
    question = create(:agent_bot_knowledge_question)

    question.knowledge_entry.destroy!

    expect(AgentBotKnowledgeQuestion.exists?(question.id)).to be(false)
  end
end
