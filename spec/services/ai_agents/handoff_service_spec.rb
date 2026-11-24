require 'rails_helper'

RSpec.describe AiAgents::HandoffService do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: { 'handoff_team_id' => team.id }) }
  let(:contact) { create(:contact, account: account, email: 'anna@example.test', additional_attributes: { 'company_name' => 'GreenSip' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :pending) }
  let(:message) { create(:message, conversation: conversation, account: account, sender: contact, content: 'Can we repay in crypto?') }
  let(:dispatcher) { Rails.configuration.dispatcher }

  def handoff(reason: 'no_answer', **)
    described_class.new(agent_bot: agent_bot, message: message, reason: reason, **)
  end

  def hand_off(...)
    handoff(...).perform
  end

  it 'sets the team, labels the conversation, leaves a note and opens the conversation, in this order' do
    allow(conversation).to receive(:bot_handoff!).and_wrap_original do |original|
      expect(conversation.reload.team).to eq(team)
      expect(conversation.label_list).to eq(['ai-handoff'])
      expect(conversation.messages.where(private: true).count).to eq(1)
      original.call
    end
    allow(dispatcher).to receive(:dispatch).and_call_original

    hand_off(reason: 'human_requested', summary: 'Wants to talk to a person.', language: 'de')

    expect(conversation).to have_received(:bot_handoff!)
    expect(conversation.reload).to have_attributes(status: 'open', team: team, waiting_since: be_present)
    expect(dispatcher).to have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation))
    expect(account.labels.find_by(title: 'ai-handoff').description).to eq('Conversations the AI agent passed to the team')
  end

  it 'leaves a private note from the bot with what the team needs' do
    expect(hand_off(summary: 'Asked whether loans can be repaid in crypto.', unanswered_question: 'Can loans be repaid in crypto?', language: 'en'))
      .to be(true)

    note = conversation.messages.where(private: true).last
    expect(note).to have_attributes(message_type: 'outgoing', sender: agent_bot)
    expect(note.content).to eq(<<~TEXT.chomp)
      The AI agent passed this conversation to the team.
      Reason: no confirmed answer in the knowledge base
      Question: Can loans be repaid in crypto?
      Company: GreenSip
      Email: anna@example.test
      Language: en
      Summary: Asked whether loans can be repaid in crypto.
    TEXT
  end

  it 'gives the last visitor message and unknown details when the reason comes from the reply service' do
    contact.update!(email: nil, additional_attributes: {})

    hand_off(reason: 'error')

    expect(conversation.messages.where(private: true).last.content).to eq(<<~TEXT.chomp)
      The AI agent passed this conversation to the team.
      Reason: the AI agent could not reply (OpenAI error)
      Question: Can we repay in crypto?
      Company: unknown
      Email: unknown
      Language: unknown
    TEXT
  end

  it 'reuses the label of the account' do
    label = create(:label, account: account, title: 'ai-handoff')

    expect { hand_off(reason: 'other') }.not_to change(Label, :count)
    expect(conversation.reload.label_list).to eq([label.title])
  end

  it 'keeps the team of the conversation without a handoff team' do
    agent_bot.update!(bot_config: {})
    other_team = create(:team, account: account)
    conversation.update!(team: other_team)

    hand_off(reason: 'other')

    expect(conversation.reload.team).to eq(other_team)
  end

  it 'leaves the team alone when the handoff team was deleted' do
    agent_bot
    team.destroy!

    hand_off(reason: 'other')

    expect(conversation.reload).to have_attributes(team: nil, status: 'open')
  end

  it 'changes nothing when an agent took the conversation over or it was resolved in the meantime' do
    agent = create(:user, account: account, role: :agent)
    conversation.update!(assignee: agent)
    other = create(:conversation, account: account, contact: contact, status: :pending)
    resolved_message = create(:message, conversation: other, account: account, sender: contact, content: 'Thanks')
    other.update!(status: :resolved)

    expect(hand_off(reason: 'human_requested')).to be(false)
    expect(described_class.new(agent_bot: agent_bot, message: resolved_message, reason: 'other').perform).to be(false)
    expect(conversation.reload).to have_attributes(status: 'pending', assignee: agent, team: nil, label_list: [])
    expect(other.reload).to have_attributes(status: 'resolved', label_list: [])
    expect(Message.where(sender: agent_bot)).to be_empty
  end

  describe '#record_unanswered_question' do
    it 'records the question with the visitor wording for no_answer' do
      recorder = instance_double(AiAgents::UnansweredRecorder, perform: nil)
      allow(AiAgents::UnansweredRecorder).to receive(:new).and_return(recorder)

      handoff(unanswered_question: 'Can loans be repaid in crypto?', visitor_question: 'Can we repay in crypto?').record_unanswered_question

      expect(AiAgents::UnansweredRecorder).to have_received(:new).with(
        agent_bot: agent_bot, conversation: conversation, message: message, question: 'Can loans be repaid in crypto?',
        visitor_question: 'Can we repay in crypto?'
      )
      expect(recorder).to have_received(:perform)
    end

    it 'records the last visitor message when the model gave no unanswered question' do
      handoff.record_unanswered_question

      expect(agent_bot.knowledge_entries.needs_answer.pluck(:question)).to eq(['Can we repay in crypto?'])
    end

    it 'records nothing for other reasons' do
      expect { handoff(reason: 'limit').record_unanswered_question }.not_to change(AgentBotKnowledgeEntry, :count)
    end
  end
end
