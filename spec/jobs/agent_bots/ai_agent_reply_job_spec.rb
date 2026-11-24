require 'rails_helper'

RSpec.describe AgentBots::AiAgentReplyJob do
  include AiAgentOpenaiHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_email_collect: false) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }
  let!(:agent_bot_inbox) { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'Hi') }
  let(:reply_service) { instance_double(AiAgents::ReplyService, perform: nil) }
  let(:lock_key) { format(described_class::LOCK_KEY, conversation_id: conversation.id) }

  before do
    allow(AiAgents::ReplyService).to receive(:new).and_return(reply_service)
  end

  after { Redis::LockManager.new.unlock(lock_key) }

  def perform
    described_class.perform_now(agent_bot.id, message.id)
  end

  it 'runs on the high queue' do
    message

    expect { described_class.perform_later(agent_bot.id, message.id) }.to have_enqueued_job(described_class).on_queue('high')
  end

  it 'replies to the latest visitor message of a pending conversation of its inbox, and releases the lock' do
    perform

    expect(AiAgents::ReplyService).to have_received(:new).with(agent_bot: agent_bot, message: message)
    expect(reply_service).to have_received(:perform)
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end

  it 'replies as the bot assigned to the conversation' do
    agent_bot_inbox.update!(status: :inactive)
    conversation.update!(assignee_agent_bot: agent_bot)

    perform

    expect(reply_service).to have_received(:perform)
  end

  it 'replies when the later bot message answers an earlier visitor message' do
    earlier = create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'Hello')
    message
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: agent_bot, message_type: :outgoing,
                     content_attributes: { ai_agent_reply_to: earlier.id })

    perform

    expect(reply_service).to have_received(:perform)
  end

  context 'when the reply is no longer wanted' do
    def expect_no_reply
      perform

      expect(reply_service).not_to have_received(:perform)
    end

    it 'skips a bot that is no longer an AI agent' do
      agent_bot.update!(bot_type: :webhook, outgoing_url: 'https://example.com/bot')

      expect_no_reply
    end

    it 'skips a bot that is no longer active in the inbox' do
      agent_bot_inbox.update!(status: :inactive)

      expect_no_reply
    end

    it 'skips a conversation that is open' do
      conversation.update!(status: :open)

      expect_no_reply
    end

    it 'skips a conversation with an assignee' do
      conversation.update!(assignee: create(:user, account: account))

      expect_no_reply
    end

    it 'skips a message that is not the latest visitor message' do
      message
      create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'One more thing')

      expect_no_reply
    end

    it 'skips a message the bot already replied to' do
      message
      create(:message, conversation: conversation, account: account, inbox: inbox, sender: agent_bot, message_type: :outgoing,
                       content_attributes: { ai_agent_reply_to: message.id })

      expect_no_reply
    end
  end

  it 'skips a message that was deleted' do
    message_id = message.id
    message.destroy!

    described_class.perform_now(agent_bot.id, message_id)

    expect(AiAgents::ReplyService).not_to have_received(:new)
  end

  it 'waits for the reply that is running in the conversation' do
    message
    Redis::LockManager.new.lock(lock_key, 60)

    expect { perform }.to have_enqueued_job(described_class).with(agent_bot.id, message.id)
    expect(reply_service).not_to have_received(:perform)
  end

  it 'releases the lock when the reply fails' do
    allow(reply_service).to receive(:perform).and_raise(ActiveRecord::RecordInvalid)

    expect { perform }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end

  context 'with the real reply' do
    let(:team) { create(:team, account: account, allow_auto_assign: false) }
    let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: { 'model' => 'gpt-agent-spec', 'handoff_team_id' => team.id }) }

    before do
      allow(AiAgents::ReplyService).to receive(:new).and_call_original
      create_ai_agent_openai_hook(account)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    end

    def bot_replies
      conversation.messages.where(sender: agent_bot, private: false)
    end

    it 'answers a message sent while the reply to an earlier one was decided, once, with both in the history' do
      follow_up = nil
      user_inputs = []
      stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return do |request|
        user_inputs << JSON.parse(request.body)['input'].select { |item| item['role'] == 'user' }.pluck('content')
        follow_up ||= create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'What does it cost?')
        { status: 200, body: openai_reply(reply: 'It costs a flat fee.').to_json }
      end

      perform
      # The job of the follow-up waited for the lock
      described_class.perform_now(agent_bot.id, follow_up.id)

      expect(user_inputs).to eq([['Hi'], ['Hi', 'What does it cost?']])
      replies = bot_replies.map { |reply| [reply.content, reply.content_attributes['ai_agent_reply_to']] }
      expect(replies).to eq([['It costs a flat fee.', follow_up.id]])
    end

    it 'completes a handoff that failed when the job runs again, with one reply' do
      stub_openai_responses(openai_tool_calls(['hand_off', { reason: 'human_requested', summary: 'Wants a person.' }]),
                            openai_reply(reply: 'A colleague will join shortly.', kind: 'handoff'))
      handoffs = 0
      allow(AiAgents::HandoffService).to receive(:new).and_wrap_original do |original, **arguments|
        original.call(**arguments).tap do |handoff|
          allow(handoff).to receive(:perform).and_wrap_original do |perform|
            handoffs += 1
            raise ActiveRecord::Deadlocked, 'deadlock detected' if handoffs == 1

            perform.call
          end
        end
      end

      expect { perform }.to raise_error(ActiveRecord::Deadlocked)
      expect(bot_replies).to be_empty
      perform

      expect(conversation.reload).to have_attributes(status: 'open', team: team, label_list: ['ai-handoff'])
      expect(bot_replies.pluck(:content)).to eq(['A colleague will join shortly.'])
    end
  end
end
