require 'rails_helper'

RSpec.describe AiAgents::Responder do
  include AiAgentOpenaiHelpers

  let(:account) { create(:account) }
  let(:bot_config) { { 'model' => 'gpt-agent-spec' } }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: bot_config) }
  let!(:page) { create(:agent_bot_page, agent_bot: agent_bot, title: 'Plans', status: :fetched, content: 'The sample plan text.') }
  let(:executor_calls) { [] }
  let(:executor) do
    lambda do |name, arguments|
      executor_calls << [name, arguments]
      name == 'hand_off' ? { team_available: true } : { saved: arguments.keys }
    end
  end
  let(:history) { [{ role: 'assistant', content: 'Hello!' }, { role: 'user', content: 'How does Scramble work?' }] }
  let(:visitor) { { name: nil, company: 'GreenSip', email_known: false, browser_language: 'de' } }
  let(:responder) { described_class.new(agent_bot: agent_bot, visitor: visitor, team_available: true, history: history, executor: executor) }

  before do
    create_ai_agent_openai_hook(account)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', category: 'Basics', question: 'How does it work?')
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-002', question: 'A draft question?', status: :draft)
    create(:agent_bot_page, agent_bot: agent_bot, title: 'Never fetched')
  end

  def tool_outputs(request)
    request['input'].select { |item| item['type'] == 'function_call_output' }.to_h { |item| [item['call_id'], JSON.parse(item['output'])] }
  end

  def static_text(request)
    request['input'].first['content'].first['text']
  end

  it 'sends a stateless request with the tools and the strict output schema' do
    requests = stub_openai_responses(openai_reply)

    responder.perform

    body = requests.first
    expect(body).to include('model' => 'gpt-agent-spec', 'store' => false, 'tool_choice' => 'auto',
                            'reasoning' => { 'effort' => AiAgents::Settings::DEFAULT_REASONING_EFFORT })
    expect(body.keys).not_to include('previous_response_id', 'include', 'instructions')
    expect(body['prompt_cache_key']).to eq("ai-agent-bot-#{agent_bot.id}")
    expect(body['tools'].pluck('name')).to eq(%w[open_page save_contact hand_off])
    expect(body['text']).to eq('format' => JSON.parse(AiAgents::Prompt::OUTPUT_FORMAT.to_json))
  end

  it 'sends the static prompt, then the facts and the history as input' do
    requests = stub_openai_responses(openai_reply)

    responder.perform

    body = requests.first
    expect(body['input'].first).to include('role' => 'developer')
    expect(static_text(body)).to start_with('FIXED RULES').and include('#KB-001 Basics | How does it work?', "[#{page.id}] Plans — #{page.url}")
    expect(static_text(body)).not_to include('A draft question?', 'Never fetched')
    expect(body['input'].second).to include('role' => 'developer')
    expect(body['input'].second['content']).to include('- Brand or company: GreenSip', '- Email: unknown', '- Browser language: de')
    expect(body['input'].drop(2)).to eq(history.map(&:stringify_keys))
  end

  it 'returns the reply with its citations and the token usage' do
    stub_openai_responses(openai_reply(reply: 'It works like this.', kind: 'answer', language: 'EN-us', entry_keys: ['#KB-001']))

    result = responder.perform

    expect(result.to_h).to include(reply: 'It works like this.', kind: 'answer', language: 'en', entry_keys: ['KB-001'], page_ids: [], grounded: true)
    expect(result.usage).to eq(requests: 1, input_tokens: 100, cached_input_tokens: 40, cache_write_tokens: 10, output_tokens: 20)
  end

  it 'runs the tools and resends the earlier output items with the tool results' do
    requests = stub_openai_responses(
      openai_tool_calls(['open_page', { page_id: page.id }], ['save_contact', { name: ' Anna ', company: nil, email: 'Anna@Example.test' }]),
      openai_reply(reply: 'The plan is described here.', kind: 'answer', page_ids: [page.id])
    )

    result = responder.perform

    second_input = requests.second['input']
    expect(second_input.find { |item| item['type'] == 'reasoning' }).to include('encrypted_content' => 'encrypted-tools')
    expect(second_input.select { |item| item['type'] == 'function_call' }.pluck('name')).to eq(%w[open_page save_contact])
    expect(tool_outputs(requests.second)).to eq(
      'call_open_page_0' => { 'title' => 'Plans', 'url' => page.url, 'content' => 'The sample plan text.' },
      'call_save_contact_1' => { 'saved' => %w[name email] }
    )
    expect(executor_calls).to eq([['save_contact', { 'name' => 'Anna', 'email' => 'anna@example.test' }]])
    expect(result.tool_calls.pluck(:name)).to eq(%w[open_page save_contact])
    expect(result.to_h).to include(grounded: true, page_ids: [page.id])
    expect(result.usage).to include(requests: 2, input_tokens: 200, cached_input_tokens: 80, cache_write_tokens: 20)
  end

  it 'reads the pages with content, also while a refresh is pending or after a failed fetch' do
    refreshing = create(:agent_bot_page, agent_bot: agent_bot, title: nil, status: :pending, content: 'Refreshing text.')
    failed = create(:agent_bot_page, agent_bot: agent_bot, title: 'Failed', status: :failed, content: 'Previous text.')
    requests = stub_openai_responses(openai_tool_calls(['open_page', { page_id: failed.id }]),
                                     openai_reply(kind: 'answer', page_ids: [refreshing.id, failed.id]))

    result = responder.perform

    expect(static_text(requests.first)).to include("[#{refreshing.id}] #{refreshing.url}\n[#{failed.id}] Failed — #{failed.url}")
    expect(tool_outputs(requests.second).values).to eq([{ 'title' => 'Failed', 'url' => failed.url, 'content' => 'Previous text.' }])
    expect(result.grounded).to be(true)
  end

  it 'returns errors to the model for a page it may not open and an invalid email, without calling the executor' do
    requests = stub_openai_responses(
      openai_tool_calls(['open_page', { page_id: page.id + 1000 }], ['save_contact', { name: nil, company: nil, email: 'anna@example' }]),
      openai_reply
    )

    result = responder.perform

    expect(tool_outputs(requests.second).values).to eq(
      [{ 'error' => 'There is no page with this id. Use an id from PAGES.' },
       { 'error' => 'The email address is not valid. Ask the visitor to check it.' }]
    )
    expect(executor_calls).to be_empty
    expect(result.tool_calls.pluck(:error)).to all(be_present)
  end

  it 'hands off once per reply' do
    hand_off = { reason: 'no_answer', summary: 'Asked about crypto.', unanswered_question: ' Can loans be repaid in crypto? ' }
    requests = stub_openai_responses(openai_tool_calls(['hand_off', hand_off], ['hand_off', hand_off.merge(reason: 'unknown')]),
                                     openai_reply(kind: 'handoff'))

    responder.perform

    expect(executor_calls).to eq(
      [['hand_off', { 'reason' => 'no_answer', 'summary' => 'Asked about crypto.', 'unanswered_question' => 'Can loans be repaid in crypto?' }]]
    )
    expect(tool_outputs(requests.second).values).to eq([{ 'team_available' => true }] * 2)
  end

  it 'stops offering tools after three tool rounds' do
    open_page = openai_tool_calls(['open_page', { page_id: page.id }])
    requests = stub_openai_responses(open_page, open_page, open_page, openai_reply)

    responder.perform

    expect(requests.pluck('tool_choice')).to eq(%w[auto auto auto none])
  end

  it 'fails when the model calls tools after the last round' do
    stub_openai_responses(openai_tool_calls(['open_page', { page_id: page.id }]))

    expect { responder.perform }.to raise_error(described_class::Error, 'OpenAI called tools after the last tool round')
    expect(responder.usage[:requests]).to eq(4)
  end

  describe 'the hand_off round' do
    let(:bot_config) { { 'model' => 'gpt-6.2-sol' } }
    let(:open_page) { openai_tool_calls(['open_page', { page_id: page.id }]) }
    let(:hand_off) { openai_tool_calls(['hand_off', { reason: 'human_requested', summary: 'Wants a person.', unanswered_question: nil }]) }
    let(:hand_off_only) { JSON.parse(described_class::HAND_OFF_ONLY.to_json) }

    it 'lets the model only hand off after the full tool rounds, with the same tools' do
      requests = stub_openai_responses(open_page, open_page, open_page, openai_reply)

      responder.perform

      expect(requests.pluck('tool_choice')).to eq(['auto', 'auto', 'auto', hand_off_only])
      expect(hand_off_only).to eq('type' => 'allowed_tools', 'mode' => 'auto', 'tools' => [{ 'type' => 'function', 'name' => 'hand_off' }])
      expect(requests.pluck('tools').uniq).to eq([JSON.parse(AiAgents::Prompt::TOOLS.to_json)])
    end

    it 'runs a hand_off of that round, then lets the model reply without tools' do
      requests = stub_openai_responses(open_page, open_page, open_page, hand_off, openai_reply(kind: 'handoff'))

      result = responder.perform

      expect(requests.pluck('tool_choice').last(2)).to eq([hand_off_only, 'none'])
      expect(executor_calls).to eq([['hand_off', { 'reason' => 'human_requested', 'summary' => 'Wants a person.', 'unanswered_question' => nil }]])
      expect(result.to_h).to include(kind: 'handoff')
      expect(result.tool_calls.pluck(:name)).to eq(%w[open_page open_page open_page hand_off])
    end

    it 'adds no round when the reply already handed off' do
      requests = stub_openai_responses(hand_off, open_page, open_page, openai_reply(kind: 'handoff'))

      responder.perform

      expect(requests.pluck('tool_choice')).to eq(%w[auto auto auto none])
    end

    it 'adds no round on older models' do
      agent_bot.update!(bot_config: { 'model' => 'gpt-4.1-mini' })
      requests = stub_openai_responses(open_page, open_page, open_page, openai_reply)

      responder.perform

      expect(requests.pluck('tool_choice')).to eq(%w[auto auto auto none])
    end
  end

  describe 'prompt caching' do
    def cache_settings(model)
      agent_bot.update!(bot_config: { 'model' => model })
      requests = stub_openai_responses(openai_reply)
      described_class.new(agent_bot: agent_bot, visitor: visitor, team_available: true, history: history, executor: executor).perform
      [requests.first['input'].first['content'].first['prompt_cache_breakpoint'], requests.first['prompt_cache_options']]
    end

    it 'ends the cached prefix after the static prompt and caches nothing else on GPT-5.6 and later' do
      expect(%w[gpt-6.2-sol gpt-6-sol gpt-5.6].map { |model| cache_settings(model) })
        .to all(eq([{ 'mode' => 'explicit', 'ttl' => '12h' }, { 'mode' => 'explicit' }]))
    end

    it 'leaves caching to older models' do
      expect(%w[gpt-4.1-mini gpt-5 o4-mini].map { |model| cache_settings(model) }).to all(eq([nil, nil]))
    end

    it 'sends the same static prompt for every conversation of the bot' do
      agent_bot.update!(bot_config: { 'model' => 'gpt-6.2-sol' })
      requests = stub_openai_responses(openai_reply)
      other_visitor = { name: 'Anna', company: nil, email_known: true, browser_language: 'en' }

      responder.perform
      described_class.new(agent_bot: agent_bot, visitor: other_visitor, team_available: false, history: [{ role: 'user', content: 'Hallo?' }],
                          executor: executor).perform

      expect(requests.first['input'].first['content'].first).to include('prompt_cache_breakpoint')
      expect(requests.first['input'].first).to eq(requests.second['input'].first)
      expect(requests.first['input'].second).not_to eq(requests.second['input'].second)
      expect(requests.pluck('prompt_cache_key').uniq).to eq(["ai-agent-bot-#{agent_bot.id}"])
    end
  end

  describe 'grounding' do
    it 'asks once more for the citations of an answer without them' do
      requests = stub_openai_responses(openai_reply(kind: 'answer'), openai_reply(reply: 'Grounded.', kind: 'answer', entry_keys: ['KB-001']))

      result = responder.perform

      correction = requests.second['input'].last
      expect(correction['role']).to eq('developer')
      expect(correction['content']).to start_with('Your reply was not sent because a reply of kind answer must cite at least one entry or page.')
      expect(requests.second['input'].find { |item| item['type'] == 'message' }).to include('id' => 'msg_reply')
      expect(result.to_h).to include(reply: 'Grounded.', grounded: true)
    end

    it 'reports a reply that cites entries that are not published or pages that are not fetched twice as not grounded' do
      requests = stub_openai_responses(openai_reply(kind: 'conversation', entry_keys: ['KB-002'], page_ids: [page.id + 1000]))

      result = responder.perform

      expect(requests.second['input'].last['content']).to include(
        'these keys are not in the KNOWLEDGE BASE: KB-002; these page ids are not in PAGES:'
      )
      expect(requests.size).to eq(2)
      expect(result.grounded).to be(false)
    end
  end

  describe 'settings' do
    let(:bot_config) { { 'reasoning_effort' => 'default' } }

    it 'uses the model of the OpenAI integration and sends no effort for the default one' do
      requests = stub_openai_responses(openai_reply)

      responder.perform

      expect(requests.first['model']).to eq(MessageTranslations::OpenaiSettings::DEFAULT_MODEL)
      expect(requests.first).not_to have_key('reasoning')
    end
  end

  describe 'errors' do
    it 'raises when OpenAI rejects the request' do
      stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL)
        .to_return(status: 500, body: { error: { message: 'The server had an error' } }.to_json)

      expect { responder.perform }.to raise_error(described_class::Error, 'The server had an error')
    end

    it 'raises when OpenAI does not answer in time' do
      stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_raise(Net::ReadTimeout)

      expect { responder.perform }.to raise_error(described_class::Error, /didn't respond within 45 seconds/)
    end

    it 'raises when the reply was cut off' do
      stub_openai_responses(openai_reply.merge(status: 'incomplete', incomplete_details: { reason: 'content_filter' }))

      expect { responder.perform }.to raise_error(described_class::Error, 'OpenAI stopped before finishing the reply (content_filter)')
    end

    it 'raises without an enabled OpenAI integration' do
      Integrations::Hook.where(account: account).delete_all

      expect { responder.perform }.to raise_error(described_class::Error, 'The OpenAI integration of the account is not enabled')
    end
  end
end
