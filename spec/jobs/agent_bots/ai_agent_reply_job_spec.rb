require 'rails_helper'

RSpec.describe AgentBots::AiAgentReplyJob do
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
      create(:message, conversation: conversation, account: account, inbox: inbox, sender: agent_bot, message_type: :outgoing)

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
end
