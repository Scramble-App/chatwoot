require 'rails_helper'

RSpec.describe AiAgents::ReplyService do
  include AiAgentOpenaiHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_email_collect: false) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:team_member) { create(:user, account: account, role: :agent) }
  let(:agent_bot) do
    create(:agent_bot, :ai_agent, account: account,
                                  bot_config: { 'model' => 'gpt-agent-spec', 'handoff_team_id' => team.id, 'max_replies_per_conversation' => 3 })
  end
  let(:contact) { create(:contact, account: account, name: 'misty-lake-42') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let!(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact, content: 'Can we repay in crypto?') }
  let(:dispatcher) { Rails.configuration.dispatcher }
  let(:events) { [] }

  before do
    create_ai_agent_openai_hook(account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'How does it work?')
    create(:inbox_member, inbox: inbox, user: team_member)
    create(:team_member, team: team, user: team_member)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    allow(dispatcher).to receive(:dispatch).and_wrap_original do |original, name, *args|
      events << name
      original.call(name, *args)
    end
  end

  def reply(to = message)
    described_class.new(agent_bot: agent_bot, message: to).perform
  end

  def bot_messages
    conversation.messages.where(sender: agent_bot).reorder(:id)
  end

  def note
    bot_messages.find_by(private: true)&.content
  end

  def visitor_message(content)
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.reload.contact, content: content)
  end

  it 'posts the reply as the bot, with the typing indicator on during the model call' do
    stub_openai_responses(openai_reply(reply: 'Scramble funds brands.', kind: 'answer', entry_keys: ['KB-001']))
    allow(Rails.logger).to receive(:info).and_call_original

    reply

    expect(bot_messages.map { |bot_message| [bot_message.message_type, bot_message.private, bot_message.content] })
      .to eq([['outgoing', false, 'Scramble funds brands.']])
    expect(bot_messages.first.content_attributes['ai_agent_reply_to']).to eq(message.id)
    typing = [Events::Types::CONVERSATION_TYPING_ON, Events::Types::CONVERSATION_TYPING_OFF, Events::Types::MESSAGE_CREATED]
    expect(events & typing).to eq(typing)
    expect(dispatcher).to have_received(:dispatch).with(Events::Types::CONVERSATION_TYPING_ON, anything,
                                                        conversation: conversation, user: agent_bot, is_private: false)
    expect(conversation.reload).to have_attributes(status: 'pending', label_list: [])
    expect(Rails.logger).to have_received(:info).with(
      "[ai-agent] conversation=#{conversation.id} agent_bot=#{agent_bot.id} model=gpt-agent-spec requests=1 " \
      'input_tokens=100 cached_input_tokens=40 cache_write_tokens=10 output_tokens=20'
    )
  end

  it 'saves the details the visitor gives to the contact and remembers the name and company for the prompt' do
    stub_openai_responses(openai_tool_calls(['save_contact', { name: 'Anna', company: 'GreenSip', email: 'anna@example.test' }]), openai_reply)

    reply

    expect(contact.reload).to have_attributes(name: 'Anna', email: 'anna@example.test', additional_attributes: include('company_name' => 'GreenSip'))
    expect(conversation.reload.additional_attributes['ai_agent_visitor']).to eq('name' => 'Anna', 'company' => 'GreenSip')
  end

  it 'merges the visitor into the contact with the email, without giving its details to the model or changing them' do
    existing = create(:contact, account: account, name: 'Jane Doe', email: 'jane@bigbrand.test',
                                additional_attributes: { 'company_name' => 'BigBrand' })
    requests = stub_openai_responses(openai_tool_calls(['save_contact', { name: nil, company: 'OtherCo', email: 'jane@bigbrand.test' }]),
                                     openai_reply)
    reply

    expect(conversation.reload.contact).to eq(existing)
    expect(existing.reload).to have_attributes(name: 'Jane Doe', additional_attributes: include('company_name' => 'BigBrand'))
    expect(requests.second['input'].last).to include('output' => { saved: %w[company email] }.to_json)

    next_requests = stub_openai_responses(openai_reply)
    reply(visitor_message('What do you know about me?'))

    context = next_requests.first['input'].second['content']
    expect(context).to include('- Name: unknown', '- Brand or company: "OtherCo"', '- Email: known')
    expect(context).not_to include('Jane Doe', 'BigBrand')
  end

  it 'keeps the name and email of the customer an email merged the visitor into, and tells the team the new email' do
    existing = create(:contact, account: account, name: 'Jane Doe', email: 'jane@bigbrand.test')
    stub_openai_responses(openai_tool_calls(['save_contact', { name: nil, company: nil, email: 'jane@bigbrand.test' }]), openai_reply)
    reply
    stub_openai_responses(openai_tool_calls(['save_contact', { name: 'Bob', company: nil, email: 'bob@elsewhere.test' }]),
                          openai_tool_calls(['hand_off', { reason: 'human_requested', summary: 'Wants a person.' }]),
                          openai_reply(kind: 'handoff'))

    reply(visitor_message("I'm Bob, and better use bob@elsewhere.test"))

    expect(existing.reload).to have_attributes(name: 'Jane Doe', email: 'jane@bigbrand.test')
    expect(conversation.reload.additional_attributes).to include('ai_agent_visitor' => { 'name' => 'Bob' },
                                                                 'ai_agent_visitor_email' => 'bob@elsewhere.test')
    expect(note).to include("Email: jane@bigbrand.test\nEmail given in chat: bob@elsewhere.test")
  end

  it 'keeps a name the contact already has' do
    contact.update!(name: 'Anna Smith')
    stub_openai_responses(openai_tool_calls(['save_contact', { name: 'Ann', company: nil, email: nil }]), openai_reply)

    reply

    expect(contact.reload.name).to eq('Anna Smith')
    expect(conversation.reload.additional_attributes['ai_agent_visitor']).to eq('name' => 'Ann')
  end

  it 'hands off, then posts the reply, when the model asks for it' do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(team_member.id.to_s => 'online')
    hand_off = { reason: 'no_answer', summary: 'Asked about crypto.', unanswered_question: 'Can loans be repaid in crypto?',
                 visitor_question: 'Can we repay in crypto?' }
    requests = stub_openai_responses(
      openai_tool_calls(['hand_off', hand_off]),
      openai_reply(reply: 'I have passed your question to the team. A colleague will join shortly.', kind: 'handoff', language: 'en')
    )

    reply

    expect(requests.first['input'].second['content']).to include('- A colleague is available now: yes')
    expect(requests.second['input'].last).to include('output' => { team_available: true }.to_json)
    expect(bot_messages.pluck(:private)).to eq([true, false])
    expect(note).to include('Reason: no confirmed answer in the knowledge base', 'Question: Can loans be repaid in crypto?', 'Language: en',
                            'Summary: Asked about crypto.')
    # The reply keeps the waiting time the handoff started
    expect(conversation.reload).to have_attributes(status: 'open', team: team, label_list: ['ai-handoff'], waiting_since: be_present)
    entry = agent_bot.knowledge_entries.needs_answer.sole
    expect([entry.question, entry.questions.sole.content]).to eq(['Can loans be repaid in crypto?', 'Can we repay in crypto?'])
  end

  it 'hands off when the reply says so without a hand_off call' do
    stub_openai_responses(openai_reply(reply: 'I have passed you to the team.', kind: 'handoff', language: 'en'))

    reply

    expect(note).to include('Reason: other')
    expect(conversation.reload).to have_attributes(status: 'open', label_list: ['ai-handoff'])
    expect(bot_messages.last.content).to eq('I have passed you to the team.')
  end

  it 'hands off and posts the fallback message without calling OpenAI when the reply limit is reached' do
    create_list(:message, 3, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot)

    reply

    expect(bot_messages.last(2).map { |bot_message| [bot_message.private, bot_message.content] }).to eq(
      [[true, note], [false, AiAgents::Defaults::FALLBACK_MESSAGE]]
    )
    expect(note).to include('Reason: the reply limit of the conversation was reached')
    expect(conversation.reload.status).to eq('open')
    expect(a_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL)).not_to have_been_made
    expect(events).not_to include(Events::Types::CONVERSATION_TYPING_ON)
  end

  it 'hands off and posts the fallback message when OpenAI fails' do
    stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return(status: 500, body: { error: { message: 'Server error' } }.to_json)

    reply

    expect(bot_messages.last.content).to eq(AiAgents::Defaults::FALLBACK_MESSAGE)
    expect(note).to include('Reason: the AI agent could not reply (OpenAI error)')
    expect(events).to include(Events::Types::CONVERSATION_TYPING_OFF)
    expect(conversation.reload.status).to eq('open')
  end

  it 'hands off and posts the fallback message when the reply is not grounded' do
    stub_openai_responses(openai_reply(reply: 'Yes, crypto works.', kind: 'answer', language: 'en'))

    reply

    expect(bot_messages.last.content).to eq(AiAgents::Defaults::FALLBACK_MESSAGE)
    expect(note).to include('Reason: the reply of the AI agent was not backed by the knowledge base', 'Language: en')
  end

  it 'keeps the reason of the hand_off the model asked for when OpenAI fails afterwards' do
    hand_off = { reason: 'no_answer', summary: 'Crypto.', unanswered_question: 'Crypto repayments?', visitor_question: nil }
    responses = [
      { status: 200, body: openai_tool_calls(['hand_off', hand_off]).to_json },
      { status: 500, body: { error: { message: 'Server error' } }.to_json }
    ]
    stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return(*responses)

    reply

    expect(bot_messages.last.content).to eq(AiAgents::Defaults::FALLBACK_MESSAGE)
    expect(note).to include('Reason: no confirmed answer in the knowledge base', 'Summary: Crypto.')
    expect(agent_bot.knowledge_entries.needs_answer.count).to eq(1)
  end

  context 'when the conversation changed during the model call' do
    # change runs during the first request, which asks for a handoff
    def stub_openai_changing(change)
      requests = 0
      stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return do
        requests += 1
        change.call if requests == 1
        body = if requests == 1
                 openai_tool_calls(['hand_off', { reason: 'human_requested', summary: 'Wants a person.' }])
               else
                 openai_reply(reply: 'A colleague will join shortly.', kind: 'handoff')
               end
        { status: 200, body: body.to_json }
      end
    end

    it 'drops the reply and its handoff when the visitor wrote again, for the newer message to answer' do
      stub_openai_changing(-> { visitor_message('And how much does it cost?') })

      reply

      expect(bot_messages).to be_empty
      expect(conversation.reload).to have_attributes(status: 'pending', label_list: [])
    end

    it 'leaves the conversation to an agent who took it over' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: agent)
      stub_openai_changing(lambda do
        conversation.update!(assignee: agent)
        create(:message, conversation: conversation, account: account, inbox: inbox, sender: agent, message_type: :outgoing, content: 'Max here.')
        conversation.update!(status: :resolved)
      end)

      reply

      expect(bot_messages).to be_empty
      expect(conversation.reload).to have_attributes(status: 'resolved', assignee: agent, label_list: [])
    end
  end
end
