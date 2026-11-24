require 'rails_helper'

RSpec.describe AiAgents::ConversationContext do
  let(:account) { create(:account) }
  # Without the email collection template, which the widget sends after the first message
  let(:inbox) { create(:inbox, account: account, enable_email_collect: false) }
  let(:contact) { create(:contact, account: account, name: 'bold-river-421') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending,
                          additional_attributes: { 'browser_language' => 'de' })
  end
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'Last question?') }
  let(:team) { nil }
  let(:context) { described_class.new(conversation: conversation, message: message, team: team) }

  describe '#visitor' do
    it 'treats a generated widget name as unknown and says only whether the email is known' do
      expect(context.visitor).to eq(name: nil, company: nil, email_known: false, browser_language: 'de')
    end

    it 'gives the name, company and email status the contact has' do
      contact.update!(name: 'Anna', email: 'anna@example.test', additional_attributes: { 'company_name' => 'GreenSip' })

      expect(context.visitor).to eq(name: 'Anna', company: 'GreenSip', email_known: true, browser_language: 'de')
    end
  end

  describe '#history' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }

    def add_message(*traits, **attributes)
      create(:message, *traits, conversation: conversation, account: account, inbox: inbox, **attributes)
    end

    it 'gives the public messages up to the message, oldest first, with their roles' do
      add_message(message_type: :incoming, sender: contact, content: 'Hi there')
      add_message(message_type: :outgoing, sender: agent_bot, content: 'Hello, I am the AI assistant.')
      add_message(message_type: :outgoing, sender: agent, content: 'A note for the team', private: true)
      add_message(message_type: :activity, sender: nil, content: 'Conversation was opened')
      add_message(message_type: :outgoing, sender: agent, content: 'I can help too.')
      add_message(:with_attachment, message_type: :incoming, sender: contact, content: "#{'x' * 2_100}\n")
      message
      add_message(message_type: :incoming, sender: contact, content: 'Sent while the reply was running')

      expect(context.history).to eq(
        [
          { role: 'user', content: 'Hi there' },
          { role: 'assistant', content: 'Hello, I am the AI assistant.' },
          { role: 'assistant', content: '[Team member] I can help too.' },
          { role: 'user', content: "#{'x' * 1_997}...\n[attachment: image]" },
          { role: 'user', content: 'Last question?' }
        ]
      )
    end

    it 'keeps the last 30 messages' do
      create_list(:message, 31, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'Earlier')
      message

      history = context.history

      expect(history.size).to eq(30)
      expect(history.last).to eq(role: 'user', content: 'Last question?')
    end
  end

  describe '#team_available?' do
    let(:team_member) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: inbox, user: team_member)
      create(:inbox_member, inbox: inbox, user: other_agent)
    end

    def online(*users)
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id)
                                                                 .and_return(users.to_h { |user| [user.id.to_s, 'online'] })
    end

    context 'with a handoff team' do
      let(:team) { create(:team, account: account) }

      before { create(:team_member, team: team, user: team_member) }

      it 'is true when a team member of the inbox is online' do
        online(team_member)

        expect(context.team_available?).to be(true)
      end

      it 'is false when only agents outside the team are online' do
        online(other_agent)

        expect(context.team_available?).to be(false)
      end
    end

    context 'without a handoff team' do
      it 'is true when any inbox member is online' do
        online(other_agent)

        expect(context.team_available?).to be(true)
      end

      it 'is false when nobody is online' do
        online

        expect(context.team_available?).to be(false)
      end
    end
  end
end
