require 'rails_helper'

RSpec.describe AiAgents::UnansweredRecorder do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:contact) { conversation.contact }
  let!(:question_message) do
    create(:message, conversation: conversation, account: account, sender: contact, content: 'Can we repay the loan in crypto, like USDT?')
  end
  let!(:message) { create(:message, conversation: conversation, account: account, sender: contact, content: 'Sure, hello@greensip.test') }
  let(:recorder) do
    described_class.new(agent_bot: agent_bot, conversation: conversation, message: message, question: 'Can loans be repaid in crypto?')
  end

  def needs_answer_entry(question)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, question: question, status: :needs_answer, short_answer: nil, answer: nil)
  end

  it 'creates a needs_answer entry with the visitor wording most similar to the question' do
    freeze_time do
      entry = recorder.perform

      expect(entry.reload).to have_attributes(question: 'Can loans be repaid in crypto?', key: 'KB-001', asked_count: 1, last_asked_at: Time.current)
      expect(entry).to be_needs_answer
      expect(entry.questions.map { |question| [question.content, question.conversation_id] })
        .to eq([[question_message.content, conversation.id]])
    end
  end

  it 'adds the question to the most similar needs_answer entry' do
    needs_answer_entry('Can a loan be repaid in crypto currency?')
    best = needs_answer_entry('Can loans be repaid in crypto or cash?')
    needs_answer_entry('Do you have an office in London?')
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, question: 'Can loans be repaid in crypto?', status: :published)

    expect { recorder.perform }.not_to change(AgentBotKnowledgeEntry, :count)
    expect(best.reload.asked_count).to eq(1)
    expect(best.questions.pluck(:content)).to eq([question_message.content])
  end

  it 'creates a new entry when no needs_answer entry is similar enough' do
    needs_answer_entry('Do you have an office in London?')

    expect { recorder.perform }.to change(agent_bot.knowledge_entries.needs_answer, :count).by(1)
  end

  it 'truncates a long wording' do
    question_message.update!(content: "#{question_message.content} #{'Details. ' * 300}")

    recorder.perform

    expect(AgentBotKnowledgeQuestion.last.content.length).to eq(AgentBotKnowledgeQuestion::CONTENT_LIMIT)
  end

  it 'retries when another conversation takes the new key at the same moment' do
    attempts = 0
    allow(agent_bot.knowledge_entries).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
      attempts += 1
      raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint' if attempts == 1

      original.call(*args, **kwargs)
    end

    entry = recorder.perform

    expect(attempts).to eq(2)
    expect(entry.reload.asked_count).to eq(1)
  end

  it 'gives up after three attempts' do
    allow(agent_bot.knowledge_entries).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    expect { recorder.perform }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(agent_bot.knowledge_entries).to have_received(:create!).exactly(3).times
  end
end
