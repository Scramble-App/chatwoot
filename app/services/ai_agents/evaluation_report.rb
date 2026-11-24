# The metrics, JSON report and summary table of an AI agent evaluation (see AiAgents::Evaluation)
class AiAgents::EvaluationReport
  RATE_LABELS = {
    correct_entry: 'Correct entry',
    no_answer_handled: 'No answer handled',
    declined: 'Declined',
    language_match: 'Language match',
    scenarios_passed: 'Scenarios passed'
  }.freeze

  # The 12-hour cache writes of the static prompt cost 2.5 times the input price
  CACHE_WRITE_PRICE_FACTOR = 2.5

  # results: the results of the cases and scenarios; prices: USD per 1M tokens, { input:, cached_input:, cache_write:, output: }
  def initialize(results:, prices:, metadata:)
    @cases = results.reject { |result| result[:type] == 'scenario' }
    @scenarios = results.select { |result| result[:type] == 'scenario' }
    @prices = prices
    @metadata = metadata
  end

  def to_h
    @metadata.merge(metrics: metrics, cases: @cases, scenarios: @scenarios)
  end

  def metrics
    @metrics ||= rates.merge(
      errors: outcomes.count { |result| result[:error] },
      ungrounded: outcomes.count { |result| result[:grounded] == false },
      latency_ms: { p50: percentile(50), p95: percentile(95) },
      tokens: tokens,
      cost_usd: cost
    )
  end

  def summary
    bot = @metadata[:bot]
    title = "AI agent evaluation of bot #{bot[:id]} (#{bot[:name]}): model #{@metadata[:model]}, " \
            "reasoning effort #{@metadata[:reasoning_effort]}, #{@metadata[:duration_seconds]} s"
    lines = [title, *table(RATE_LABELS.to_h { |key, label| [label, rate_text(metrics[key])] }.merge(usage_rows))]
    lines += ['', 'Failed:', *failure_lines] if failure_lines.any?
    lines.join("\n")
  end

  private

  def rates
    {
      correct_entry: rate(@cases.select { |result| result[:expected_key] }) { |result| entry_correct?(result) },
      no_answer_handled: rate(@cases.select { |result| result[:expect] == 'no_answer' }) { |result| result[:passed] },
      declined: rate(@cases.select { |result| result[:expect] == 'decline' }) { |result| result[:passed] },
      language_match: rate(outcomes.select { |result| result[:expected_language] }) { |result| language_match?(result) },
      scenarios_passed: rate(@scenarios) { |result| result[:passed] }
    }
  end

  # Every run of the Responder: the cases and the scenario turns that ran
  def outcomes
    @outcomes ||= @cases + @scenarios.flat_map { |scenario| scenario[:turns] }.reject { |turn| turn[:skipped] }
  end

  def rate(items, &)
    passed = items.count(&)
    { passed: passed, total: items.size, rate: items.empty? ? nil : (passed.to_f / items.size).round(3) }
  end

  def entry_correct?(result)
    result[:error].nil? && result[:grounded] && result[:kind] == 'answer' && result[:entry_keys].include?(result[:expected_key])
  end

  def language_match?(result)
    result[:language].present? && result[:language] == result[:expected_language].to_s.downcase
  end

  # Nearest rank
  def percentile(percent)
    latencies = outcomes.filter_map { |result| result[:latency_ms] }.sort
    latencies[((percent / 100.0) * latencies.size).ceil - 1] if latencies.any?
  end

  def tokens
    @tokens ||= %i[requests input_tokens cached_input_tokens cache_write_tokens output_tokens].index_with do |key|
      outcomes.sum { |result| result.dig(:usage, key).to_i }
    end
  end

  # The input tokens include the cached and the cache write tokens
  def cost
    input = price(:input)
    output = price(:output)
    return if input.nil? || output.nil?

    ordinary_tokens = tokens[:input_tokens] - tokens[:cached_input_tokens] - tokens[:cache_write_tokens]
    usd = (ordinary_tokens * input) + token_prices(input, output).sum { |key, token_price| tokens[key] * token_price }
    usd / 1_000_000.0
  end

  # Without their own prices, cached tokens cost the input price and cache writes 2.5 times the input price
  def token_prices(input, output)
    {
      cached_input_tokens: price(:cached_input) || input,
      cache_write_tokens: price(:cache_write) || (input * CACHE_WRITE_PRICE_FACTOR),
      output_tokens: output
    }
  end

  def price(key)
    Float(@prices[key], exception: false) if @prices[key].present?
  end

  def usage_rows
    {
      'Errors' => metrics[:errors],
      'Ungrounded replies' => metrics[:ungrounded],
      'Latency p50 / p95' => metrics[:latency_ms].values.map { |value| value ? "#{(value / 1000.0).round(1)} s" : 'n/a' }.join(' / '),
      'OpenAI requests' => tokens[:requests],
      'Tokens input / cached / cache write / output' => tokens.except(:requests).values.join(' / '),
      'Estimated cost' => metrics[:cost_usd] ? format('$%.4f', metrics[:cost_usd]) : 'n/a, set INPUT_PRICE_PER_1M and OUTPUT_PRICE_PER_1M'
    }
  end

  def table(rows)
    width = rows.keys.map(&:length).max
    rows.map { |label, value| "#{label.ljust(width)}  #{value}" }
  end

  def rate_text(rate)
    return 'n/a' if rate[:total].zero?

    "#{rate[:passed]}/#{rate[:total]} (#{(rate[:rate] * 100).round(1)}%)"
  end

  def failure_lines
    @failure_lines ||= @cases.reject { |result| result[:passed] }.map { |result| "#{result[:type]} #{result[:id]}: #{result[:failures].join('; ')}" }
                             .concat(@scenarios.reject { |result| result[:passed] }.flat_map { |result| scenario_failure_lines(result) })
  end

  def scenario_failure_lines(scenario)
    scenario[:turns].each_with_index.reject { |turn, _index| turn[:passed] }.map do |turn, index|
      "scenario #{scenario[:id]}, turn #{index + 1}: #{turn[:failures].join('; ')}"
    end
  end
end
