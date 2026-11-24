# Checks one run of the AI agent in an evaluation against what the case or scenario turn expects, and lists the failures.
# The expectations are documented at the top of the YAML file of cases.
class AiAgents::EvaluationCheck
  TURN_EXPECTATIONS = %w[kind tools_include tools_exclude keys_include language reply_matches reply_not_matches].freeze

  # outcome: { reply:, kind:, language:, entry_keys:, page_ids:, grounded:, tools:, error: } of a Responder run
  def initialize(outcome)
    @outcome = outcome
  end

  # expect: answer, no_answer or decline
  def case_failures(expect:, expected_key: nil, expected_language: nil)
    return ["error: #{@outcome[:error]}"] if @outcome[:error]

    [grounding_failure, *expect_failures(expect, expected_key), (language_failure(expected_language) if expected_language)].compact
  end

  # expect: the expectations of a scenario turn
  def turn_failures(expect)
    return ["error: #{@outcome[:error]}"] if @outcome[:error]

    failures = expect.slice(*TURN_EXPECTATIONS).map { |name, value| send(:"#{name}_failure", value) }
    [grounding_failure, *failures].compact
  end

  private

  def expect_failures(expect, expected_key)
    case expect
    when 'answer' then [kind_failure('answer'), (keys_include_failure(expected_key) if expected_key)]
    when 'no_answer' then [answered_failure]
    when 'decline' then [answered_failure, tools_exclude_failure('hand_off')]
    else ["unknown expect: #{expect}"]
    end
  end

  # The reply service would send the fallback message instead
  def grounding_failure
    'the reply is not grounded' unless @outcome[:grounded]
  end

  def answered_failure
    'it answered' if @outcome[:kind] == 'answer'
  end

  def kind_failure(kinds)
    kinds = Array(kinds)
    "kind is #{@outcome[:kind]}, not #{kinds.join(' or ')}" if kinds.exclude?(@outcome[:kind])
  end

  def tools_include_failure(names)
    list_failure(Array(names) - tool_names, 'not called')
  end

  def tools_exclude_failure(names)
    list_failure(Array(names) & tool_names, 'called')
  end

  def keys_include_failure(keys)
    list_failure(Array(keys) - @outcome[:entry_keys], 'not cited')
  end

  def language_failure(language)
    "language is #{@outcome[:language].presence || 'unknown'}, not #{language}" unless @outcome[:language] == language.to_s.downcase
  end

  def reply_matches_failure(pattern)
    "the reply doesn't match /#{pattern}/" unless reply_matches?(pattern)
  end

  def reply_not_matches_failure(pattern)
    "the reply matches /#{pattern}/" if reply_matches?(pattern)
  end

  def reply_matches?(pattern)
    Regexp.new(pattern, Regexp::IGNORECASE).match?(@outcome[:reply].to_s)
  end

  def list_failure(items, problem)
    "#{items.join(', ')} #{problem}" if items.any?
  end

  def tool_names
    @outcome[:tools].pluck(:name)
  end
end
