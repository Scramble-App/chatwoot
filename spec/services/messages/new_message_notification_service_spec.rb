require 'rails_helper'

describe Messages::NewMessageNotificationService do
  context 'when message is not notifiable' do
    it 'will not create any notifications for activity messages' do
      message = build(:message, message_type: :activity)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end

    it 'will not create any notifications for private messages' do
      message = build(:message, message_type: :outgoing, private: true)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end
  end

  context 'when message is notifiable' do
    let(:account) { create(:account) }
    let(:assignee) { create(:user, account: account) }
    let(:participating_agent_1) { create(:user, account: account) }
    let(:participating_agent_2) { create(:user, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assignee) }

    before do
      create(:inbox_member, inbox: inbox, user: participating_agent_1)
      create(:inbox_member, inbox: inbox, user: participating_agent_2)
      create(:inbox_member, inbox: inbox, user: assignee)
      create(:conversation_participant, conversation: conversation, user: participating_agent_1)
      create(:conversation_participant, conversation: conversation, user: participating_agent_2)
      create(:conversation_participant, conversation: conversation, user: assignee)
    end

    context 'when message is created by a participant' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: participating_agent_1) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates notifications for other participating users' do
        expect(participating_agent_2.notifications.where(notification_type: 'participating_conversation_new_message', account: account,
                                                         primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'creates notifications for assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'will not create notifications for the user who created the message' do
        expect(participating_agent_1.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).not_to exist
      end
    end

    context 'when message is created by a contact' do
      let(:message) { create(:message, conversation: conversation, account: account) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates notifications for assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'creates notifications for all participating users' do
        expect(participating_agent_1.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).to exist
        expect(participating_agent_2.notifications.where(notification_type: 'participating_conversation_new_message',
                                                         account: account, primary_actor: message.conversation,
                                                         secondary_actor: message)).to exist
      end
    end

    context 'when multiple notification conditions are met' do
      let(:message) { create(:message, conversation: conversation, account: account) }

      before do
        described_class.new(message: message).perform
      end

      it 'will not create participating notifications for the assignee if assignee notification was send' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).to exist
        expect(assignee.notifications.where(notification_type: 'participating_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
      end
    end

    context 'when message is created by assignee' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: assignee) }

      before do
        described_class.new(message: message).perform
      end

      it 'will not create notifications for the user who created the message' do
        expect(assignee.notifications.where(notification_type: 'participating_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message',
                                            account: account, primary_actor: message.conversation,
                                            secondary_actor: message)).not_to exist
      end
    end
  end

  context 'when an AI agent bot answers the inbox' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account) }
    let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }
    let!(:agent_bot_inbox) { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
    let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox) }

    before do
      create(:inbox_member, inbox: inbox, user: agent)
      create(:conversation_participant, conversation: conversation, user: agent)
    end

    def notified?(notification_type)
      described_class.new(message: message).perform
      agent.notifications.exists?(notification_type: notification_type, secondary_actor: message)
    end

    it 'does not notify the agents who took part while it answers the pending conversation' do
      expect(notified?('participating_conversation_new_message')).to be(false)
    end

    it 'notifies them once the conversation is handed over' do
      conversation.update!(status: :open)

      expect(notified?('participating_conversation_new_message')).to be(true)
    end

    it 'notifies the assignee of a pending conversation an agent took' do
      conversation.update!(assignee: agent)

      expect(notified?('assigned_conversation_new_message')).to be(true)
    end

    it 'notifies them when the bot is inactive' do
      agent_bot_inbox.update!(status: :inactive)

      expect(notified?('participating_conversation_new_message')).to be(true)
    end

    it 'notifies them for a webhook bot' do
      agent_bot.update!(bot_type: :webhook, outgoing_url: 'https://example.com/bot')

      expect(notified?('participating_conversation_new_message')).to be(true)
    end
  end
end
