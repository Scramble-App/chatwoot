require 'rails_helper'

RSpec.describe AiAgents::UnansweredRecorder do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:contact) { conversation.contact }
  let!(:question_message) { visitor_message('Can we repay the loan in crypto, like USDT?') }
  let!(:message) { visitor_message('Sure, hello@greensip.test') }
  let(:recorder) { recorder_for }

  def visitor_message(content)
    create(:message, conversation: conversation, account: account, sender: contact, content: content)
  end

  def recorder_for(question: 'Can loans be repaid in crypto?', visitor_question: nil, to: message)
    described_class.new(agent_bot: agent_bot, conversation: conversation, message: to, question: question, visitor_question: visitor_question)
  end

  def needs_answer_entry(question)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, question: question, status: :needs_answer, short_answer: nil, answer: nil)
  end

  def recorded_wording(...)
    recorder_for(...).perform.questions.last.content
  end

  it 'creates a needs_answer entry with the latest visitor message that asks something, not one that only gives an email' do
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

  context 'with a conversation in a language written without spaces' do
    it 'takes a question with a full-width question mark, not an acknowledgement' do
      contents = %w[你好 可以用加密货币还款吗？ 好的]
      messages = contents.map { |content| visitor_message(content) }

      expect(recorded_wording(question: 'Can loans be repaid in crypto?', to: messages.last)).to eq('可以用加密货币还款吗？')
    end

    it 'takes a longer message without a question mark as a question' do
      visitor_message('我想了解一下加密货币还款')
      acknowledgement = visitor_message('好的')

      expect(recorded_wording(question: 'Can loans be repaid in crypto?', to: acknowledgement)).to eq('我想了解一下加密货币还款')
    end
  end

  context 'with a conversation in another language' do
    let(:question) { 'How is the payout of a refinancing loan calculated?' }
    let(:accepted) { visitor_message('Да, передайте, пожалуйста') }

    before do
      # The oldest message shares a Latin acronym with English, the question is in the third one
      visitor_message('Здравствуйте! В договоре вижу APR очень высокий, почему так?')
      visitor_message('Понятно, спасибо')
      visitor_message('Как считается сумма нового займа при рефинансировании?')
    end

    it 'stores the visitor words the model copied' do
      copy = "как считается  сумма нового займа\nпри рефинансировании"

      expect(recorded_wording(question: question, visitor_question: copy,
                              to: accepted)).to eq('как считается сумма нового займа при рефинансировании')
    end

    it 'stores the message itself when the copy holds a whole message that asks something, and more' do
      copy = 'Как считается сумма нового займа при рефинансировании? And can we repay it in crypto?'

      expect(recorded_wording(question: question, visitor_question: copy,
                              to: accepted)).to eq('Как считается сумма нового займа при рефинансировании?')
    end

    it 'does not take a short copy, such as an acronym, for the wording' do
      expect(recorded_wording(question: question, visitor_question: 'APR',
                              to: accepted)).to eq('Как считается сумма нового займа при рефинансировании?')
    end

    it 'falls back to the latest message that asks something when the copy is not in the conversation' do
      expect(recorded_wording(question: question, visitor_question: question,
                              to: accepted)).to eq('Как считается сумма нового займа при рефинансировании?')
      expect(recorded_wording(question: question, to: accepted)).to eq('Как считается сумма нового займа при рефинансировании?')
    end

    it 'does not take a short reply for the whole message in the copy' do
      copy = 'Да, а как считается выплата? Понятно, спасибо'
      visitor_message('Да')

      expect(recorded_wording(question: question, visitor_question: copy,
                              to: accepted)).to eq('Как считается сумма нового займа при рефинансировании?')
    end
  end
end
