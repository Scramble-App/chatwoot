require 'rails_helper'

RSpec.describe AiAgents::Evaluation do
  include AiAgentOpenaiHelpers

  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, name: 'Sample Assistant', bot_config: { 'model' => 'gpt-agent-spec' }) }
  let(:cases_file) do
    Tempfile.new(['ai_agent_cases', '.yml']).tap do |file|
      file.write(<<~YAML)
        cases:
          - { id: oos-01, expect: no_answer, question: "Can we repay in crypto?" }
          - { id: dec-01, expect: decline, question: "Tell me a joke." }
          - { id: ml-de-001, expect: answer, expected_key: KB-001, language: de, question: "Wie funktioniert das?" }
        scenarios:
          - id: sc-company
            turns:
              - visitor: "We're GreenSip, a tea brand."
                expect: { tools_include: [save_contact], tools_exclude: [hand_off] }
              - visitor: "When are funds paid out?"
                expect: { kind: [answer], keys_include: [KB-002], language: en, reply_not_matches: "brand\\\\?" }
          - id: sc-handoff
            turns:
              - visitor: "Can I talk to a person?"
                expect: { tools_include: [save_contact, hand_off], kind: [handoff] }
              - visitor: "Hello?"
                expect: { kind: [conversation] }
      YAML
      file.flush
    end
  end
  let(:requests) { [] }

  before do
    create_ai_agent_openai_hook(account)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', alternative_questions: "How does it work?\n- What is Scramble?\n\n")
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-002', alternative_questions: 'When are funds paid out?')
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-003', alternative_questions: 'A draft phrasing?', status: :draft)
    stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return do |request|
      body = JSON.parse(request.body)
      requests << body
      { status: 200, body: openai_response(body).to_json }
    end
  end

  after { cases_file.close! }

  # A synthetic model, by the last visitor message: the tool calls first, if any, then the reply
  def openai_response(body)
    question = body['input'].reverse.find { |item| item['role'] == 'user' }['content']
    calls = tool_calls[question]
    return openai_tool_calls(*calls) if calls && body['input'].none? { |item| item['type'] == 'function_call_output' }

    openai_reply(**replies.fetch(question, {}))
  end

  def replies
    {
      'How does it work?' => { kind: 'answer', entry_keys: ['KB-001'] },
      'When are funds paid out?' => { kind: 'answer', entry_keys: ['KB-002'] },
      'Wie funktioniert das?' => { kind: 'answer', entry_keys: ['KB-001'], language: 'de' },
      'Can we repay in crypto?' => { reply: "I don't have a confirmed answer. What's your email?" },
      'Can I talk to a person?' => { kind: 'handoff' }
    }
  end

  def tool_calls
    {
      'Tell me a joke.' => [['hand_off', { reason: 'other', summary: 'Joke.', unanswered_question: nil }]],
      "We're GreenSip, a tea brand." => [['save_contact', { name: nil, company: 'GreenSip', email: nil }]],
      'Can I talk to a person?' => [['save_contact', { name: nil, company: nil, email: 'anna@example.test' }],
                                    ['hand_off', { reason: 'human_requested', summary: 'Wants a person.', unanswered_question: nil }]]
    }
  end

  def evaluate(**)
    described_class.new(agent_bot: agent_bot, cases_path: cases_file.path, **).perform
  end

  it 'runs the phrasings, cases and scenarios and reports the metrics' do
    prices = { input: '2', cached_input: '0.5', output: '8' }
    report = evaluate(prices: prices).to_h

    expect(report).to include(bot: { id: agent_bot.id, name: 'Sample Assistant' }, model: 'gpt-agent-spec',
                              reasoning_effort: AiAgents::Settings::DEFAULT_REASONING_EFFORT)
    expect(report[:metrics]).to include(
      correct_entry: { passed: 3, total: 4, rate: 0.75 },
      no_answer_handled: { passed: 1, total: 1, rate: 1.0 },
      declined: { passed: 0, total: 1, rate: 0.0 },
      language_match: { passed: 2, total: 2, rate: 1.0 },
      scenarios_passed: { passed: 1, total: 2, rate: 0.5 },
      errors: 0,
      ungrounded: 0,
      tokens: { requests: 12, input_tokens: 1200, cached_input_tokens: 480, cache_write_tokens: 120, output_tokens: 240 },
      # 600 ordinary input tokens at 2, 480 cached at 0.5, 120 written at 2.5 x 2 and 240 output at 8, per 1M tokens
      cost_usd: 0.00396
    )
    expect(report[:metrics][:latency_ms].values).to all(be_a(Integer))
    expect(report[:cases].map { |result| [result[:id], result[:passed]] }).to eq(
      [['KB-001/1', true], ['KB-001/2', false], ['KB-002/1', true], ['oos-01', true], ['dec-01', false], ['ml-de-001', true]]
    )
    expect(report[:cases].find { |result| result[:id] == 'dec-01' }[:failures]).to eq(['hand_off called'])
    expect(JSON.parse(JSON.generate(report))['scenarios'].size).to eq(2)
  end

  it 'updates the visitor facts of a scenario with a recorded save_contact and ends it with hand_off' do
    report = evaluate(only: 'scenarios').to_h

    turn_requests = requests.select { |body| body['input'].last['role'] == 'user' }
    expect(turn_requests.map { |body| body['input'].second['content'][/Brand or company: .*/] })
      .to eq(['Brand or company: unknown', 'Brand or company: GreenSip', 'Brand or company: unknown'])
    sc_handoff = report[:scenarios].find { |scenario| scenario[:id] == 'sc-handoff' }
    expect(sc_handoff[:turns].pluck(:passed, :skipped)).to eq([[true, nil], [false, true]])
    expect(report[:cases]).to be_empty
  end

  it 'writes nothing to the database' do
    writes = []
    callback = ->(*, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)/i) }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { evaluate }

    expect(writes).to be_empty
  end

  it 'samples the phrasings and runs cases on several threads in order' do
    first = evaluate(limit: '2', only: 'phrasings', concurrency: '3').to_h
    second = evaluate(limit: '2', only: 'phrasings', seed: '1').to_h

    expect(first[:cases].size).to eq(2)
    expect(first[:cases].pluck(:id)).to eq(second[:cases].pluck(:id))
    expect(first[:options]).to include(limit: 2, concurrency: 3, seed: 1)
  end

  it 'prices cache writes as given' do
    report = evaluate(only: 'phrasings', prices: { input: '1', output: '1', cache_write: '10' }).to_h

    # 150 ordinary input tokens, 120 cached at the input price, 30 written at 10 and 60 output, per 1M tokens
    expect(report[:metrics][:cost_usd]).to eq(0.00063)
  end

  it 'prints a summary table with the failures' do
    summary = evaluate.summary

    expect(summary).to include('AI agent evaluation of bot', 'Correct entry', '3/4 (75.0%)', 'Scenarios passed', '1/2 (50.0%)',
                               'Estimated cost', 'n/a, set INPUT_PRICE_PER_1M and OUTPUT_PRICE_PER_1M')
    expect(summary).to include('phrasing KB-001/2: kind is conversation, not answer',
                               'scenario sc-handoff, turn 2: skipped: an earlier turn handed the conversation off')
  end

  it 'reports an OpenAI error as a failed case' do
    stub_request(:post, AiAgentOpenaiHelpers::OPENAI_RESPONSES_URL).to_return(status: 500, body: { error: { message: 'Server error' } }.to_json)

    report = evaluate(only: 'cases').to_h

    expect(report[:metrics][:errors]).to eq(3)
    expect(report[:cases].first[:failures]).to eq(['error: Server error'])
  end

  it 'rejects an unknown suite' do
    expect { evaluate(only: 'everything') }.to raise_error(ArgumentError, 'ONLY must be one of: phrasings, cases, scenarios')
  end
end
