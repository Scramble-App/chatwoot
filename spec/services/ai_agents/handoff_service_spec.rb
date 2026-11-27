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

  it 'leaves a note, then sets the team, the label and the open status in one save' do
    saves = []
    allow(conversation).to receive(:update!).and_wrap_original do |original, changes|
      expect(conversation.messages.where(private: true).count).to eq(1)
      saves << changes
      original.call(changes)
    end
    allow(dispatcher).to receive(:dispatch).and_call_original

    hand_off(reason: 'human_requested', summary: 'Wants to talk to a person.', language: 'de')

    expect(saves).to match([include(team: team, label_list: ['ai-handoff'], status: :open)])
    expect(conversation.reload).to have_attributes(status: 'open', team: team, label_list: ['ai-handoff'])
    # Sent by the caller, once the handoff is committed
    expect(dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, any_args)
    expect(account.labels.find_by(title: 'ai-handoff').description).to eq('Conversations the AI agent passed to the team')
  end

  it 'keeps the time the visitor has been waiting since' do
    waiting_since = 5.minutes.ago.change(usec: 0)
    message
    conversation.update!(waiting_since: waiting_since)

    hand_off(reason: 'other')

    expect(conversation.reload.waiting_since).to eq(waiting_since)
  end

  it 'starts the wait for the team when the visitor was not waiting, like bot_handoff!' do
    message
    conversation.update!(waiting_since: nil)

    freeze_time do
      hand_off(reason: 'other')

      expect(conversation.reload.waiting_since).to eq(Time.current)
    end
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

  context 'when the conversation has the handoff team already, as after the visitor wrote again' do
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: conversation.inbox, user: agent)
      create(:team_member, team: team, user: agent)
      conversation.update!(team: team)
      conversation.inbox.update!(enable_auto_assignment: false)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
    end

    it 'assigns an online agent of the team, as setting the team does' do
      team.update!(allow_auto_assign: true)

      hand_off(reason: 'human_requested')

      expect(conversation.reload).to have_attributes(status: 'open', team: team, assignee: agent)
    end

    it 'leaves it unassigned when the team does not auto assign' do
      hand_off(reason: 'human_requested')

      expect(conversation.reload).to have_attributes(status: 'open', team: team, assignee: nil)
    end
  end

  it 'leaves the team alone when the handoff team was deleted' do
    agent_bot
    team.destroy!

    hand_off(reason: 'other')

    expect(conversation.reload).to have_attributes(team: nil, status: 'open')
  end

  it 'hands off all or nothing, so a failed handoff is done again cleanly' do
    saves = 0
    allow(conversation).to receive(:update!).and_wrap_original do |original, *arguments|
      original.call(*arguments).tap do
        saves += 1
        raise ActiveRecord::Deadlocked, 'deadlock detected' if saves == 1
      end
    end

    expect { hand_off(reason: 'human_requested') }.to raise_error(ActiveRecord::Deadlocked)
    expect(conversation.reload).to have_attributes(status: 'pending', team: nil, label_list: [])
    expect(conversation.messages.where(private: true)).to be_empty

    hand_off(reason: 'human_requested')

    expect(conversation.reload).to have_attributes(status: 'open', team: team, label_list: ['ai-handoff'])
    expect(conversation.messages.where(private: true).count).to eq(1)
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

  describe '#dispatch_event' do
    it 'sends the event bot_handoff! sends' do
      service = handoff(reason: 'human_requested')
      service.perform
      allow(dispatcher).to receive(:dispatch)

      service.dispatch_event

      expect(dispatcher).to have_received(:dispatch).with(
        Events::Types::CONVERSATION_BOT_HANDOFF, anything,
        conversation: conversation, notifiable_assignee_change: false, changed_attributes: nil, performed_by: nil
      )
    end
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
