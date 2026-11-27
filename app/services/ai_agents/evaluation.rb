# The eval harness of an AI agent bot (rake ai_agent:evaluate). Runs the Responder on the bot's own phrasings (each line
# of alternative_questions of a published entry must be answered from that entry) and on the cases and scenarios of a
# YAML file, whose format is documented at the top of the file. Tools are recorded, not executed: save_contact updates
# the visitor facts of a scenario and hand_off ends it. Nothing is written to the database.
class AiAgents::Evaluation
  SUITES = %w[phrasings cases scenarios].freeze
  MAX_CONCURRENCY = 4
  DEFAULT_SEED = 1
  # The team fact of the prompt and the hand_off result
  TEAM_AVAILABLE = true
  VISITOR = { name: nil, company: nil, email_known: false, browser_language: nil }.freeze
  # The reply service hands off after hand_off, an error or a reply that isn't grounded
  HANDED_OFF = 'skipped: an earlier turn handed the conversation off'.freeze

  # limit: the sample size of phrasings (all by default), drawn with seed; only: one of SUITES; concurrency: 1 to 4;
  # prices: USD per 1M tokens, { input:, cached_input:, cache_write:, output: }
  def initialize(agent_bot:, cases_path: nil, limit: nil, only: nil, concurrency: nil, seed: nil, prices: {}) # rubocop:disable Metrics/ParameterLists
    @agent_bot = agent_bot
    @cases_path = cases_path.presence
    @limit = limit.presence&.to_i
    @only = only.presence
    @concurrency = (concurrency.presence || 1).to_i.clamp(1, MAX_CONCURRENCY)
    @seed = (seed.presence || DEFAULT_SEED).to_i
    @prices = prices
    raise ArgumentError, "ONLY must be one of: #{SUITES.join(', ')}" if @only && SUITES.exclude?(@only)
  end

  # Yields a progress line per finished case or scenario; returns an AiAgents::EvaluationReport
  def perform(&progress)
    hook = MessageTranslations::OpenaiSettings.hook_for(@agent_bot.account)
    raise ArgumentError, 'The OpenAI integration of the account is not enabled' if hook.blank?

    started_at = Time.current
    started = clock
    results = run(units, progress)
    AiAgents::EvaluationReport.new(results: results, prices: @prices, metadata: metadata(hook, started_at, clock - started))
  end

  private

  def metadata(hook, started_at, duration)
    settings = @agent_bot.ai_agent_settings
    {
      bot: { id: @agent_bot.id, name: @agent_bot.name },
      model: settings.model || MessageTranslations::OpenaiSettings.model(hook),
      reasoning_effort: settings.reasoning_effort,
      options: { cases: @cases_path, limit: @limit, only: @only, concurrency: @concurrency, seed: @seed },
      started_at: started_at.iso8601,
      duration_seconds: duration.round(1)
    }
  end

  def units
    [
      *(phrasings if suite?('phrasings')),
      *(yaml_cases if suite?('cases')),
      *(scenarios if suite?('scenarios'))
    ]
  end

  def suite?(name)
    @only.nil? || @only == name
  end

  def phrasings
    all = @agent_bot.knowledge_entries.published.order(:id).flat_map { |entry| entry_phrasings(entry) }
    @limit ? all.sample(@limit, random: Random.new(@seed)) : all
  end

  # One phrasing per line, without list bullets
  def entry_phrasings(entry)
    questions = entry.alternative_questions.to_s.lines.filter_map { |line| line.strip.sub(/\A[-*•]\s+/, '').presence }
    questions.map.with_index(1) do |question, index|
      { type: 'phrasing', id: "#{entry.key}/#{index}", question: question, expect: 'answer', expected_key: entry.key }
    end
  end

  def yaml_cases
    Array(cases_file['cases']).map do |item|
      { type: 'case', id: item['id'], question: item['question'], expect: item['expect'], expected_key: item['expected_key'],
        expected_language: item['language'] }
    end
  end

  def scenarios
    Array(cases_file['scenarios']).map { |item| { type: 'scenario', id: item['id'], turns: Array(item['turns']) } }
  end

  def cases_file
    @cases_file ||= (@cases_path && YAML.safe_load_file(@cases_path)) || {}
  end

  # Workers take cases and scenarios from a queue; the turns of a scenario run in order
  def run(units, progress)
    queue = Queue.new
    units.each_with_index { |unit, index| queue << [unit, index] }
    queue.close
    results = Array.new(units.size)
    workers = Array.new([@concurrency, units.size].min) do
      Thread.new { Rails.application.executor.wrap { work(queue, results, progress) } }
    end
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { workers.each(&:join) }
    results
  end

  def work(queue, results, progress)
    while (unit, index = queue.pop)
      results[index] = run_unit(unit)
      progress&.call(progress_line(results[index], results.count(&:present?), results.size))
    end
  end

  def run_unit(unit)
    unit[:type] == 'scenario' ? run_scenario(unit) : run_case(unit)
  end

  def run_case(unit)
    outcome = respond([{ role: 'user', content: unit[:question] }], VISITOR.dup)
    failures = AiAgents::EvaluationCheck.new(outcome).case_failures(**unit.slice(:expect, :expected_key, :expected_language))
    unit.merge(outcome, failures: failures, passed: failures.empty?)
  end

  def run_scenario(unit)
    visitor = VISITOR.dup
    history = []
    turns = []
    unit[:turns].each do |turn|
      turns << (ended?(turns.last) ? skipped_turn(turn) : run_turn(turn, visitor, history))
    end
    { type: 'scenario', id: unit[:id], turns: turns, passed: turns.all? { |turn| turn[:passed] } }
  end

  def ended?(turn)
    turn.present? && (turn[:skipped] || turn[:handed_off] || turn[:error].present? || !turn[:grounded])
  end

  def skipped_turn(turn)
    { visitor: turn['visitor'], expect: turn['expect'] || {}, skipped: true, failures: [HANDED_OFF], passed: false }
  end

  def run_turn(turn, visitor, history)
    expect = turn['expect'] || {}
    history << { role: 'user', content: turn['visitor'] }
    outcome = respond(history.dup, visitor)
    history << { role: 'assistant', content: outcome[:reply] } if outcome[:reply]
    failures = AiAgents::EvaluationCheck.new(outcome).turn_failures(expect)
    { visitor: turn['visitor'], expect: expect, expected_language: expect['language'] }.merge(outcome, failures: failures, passed: failures.empty?)
  end

  # visitor: the facts of the conversation, which a recorded save_contact updates for the next turns
  def respond(history, visitor)
    handed_off = false
    executor = lambda do |name, arguments|
      handed_off ||= name == 'hand_off'
      name == 'hand_off' ? { team_available: TEAM_AVAILABLE } : record_contact(visitor, arguments)
    end
    responder = AiAgents::Responder.new(agent_bot: @agent_bot, visitor: visitor.dup, team_available: TEAM_AVAILABLE, history: history,
                                        executor: executor)
    started = clock
    outcome = begin
      responder.perform.to_h.slice(:reply, :kind, :language, :entry_keys, :page_ids, :grounded)
    rescue AiAgents::Responder::Error => e
      { error: e.message }
    end
    outcome.merge(tools: responder.tool_calls, handed_off: handed_off, latency_ms: ((clock - started) * 1000).round, usage: responder.usage)
  end

  def record_contact(visitor, details)
    visitor[:name] = details['name'] if details['name']
    visitor[:company] = details['company'] if details['company']
    visitor[:email_known] = true if details['email']
    { saved: details.keys }
  end

  def progress_line(result, done, total)
    failures = result[:type] == 'scenario' ? scenario_failures(result) : result[:failures]
    "[#{done}/#{total}] #{result[:type]} #{result[:id]}: #{failures.empty? ? 'ok' : "FAIL #{failures.join('; ')}"}"
  end

  def scenario_failures(result)
    result[:turns].each_with_index.flat_map { |turn, index| turn[:failures].map { |failure| "turn #{index + 1}: #{failure}" } }
  end

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
