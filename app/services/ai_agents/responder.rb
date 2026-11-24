# Decides the reply of an AI agent bot without changing anything: builds the prompt, runs the OpenAI tool loop and checks
# that the reply is grounded in the knowledge base or the pages. open_page only reads, so it runs here; save_contact and
# hand_off go to the executor, which acts on them (AiAgents::ReplyService) or records them (AiAgents::Evaluation).
#
# The request is stateless (store: false), so every round resends the whole input plus the output items of the earlier
# rounds, reasoning items included, and the function_call_output items. Stateless responses carry the encrypted reasoning
# content by default, so no include parameter is needed.
#
# The static prompt, the same for every conversation of the bot, is the first input message so OpenAI can cache it. On
# GPT-5.6 and later it ends with an explicit cache breakpoint, and explicit mode keeps the rest of the request out of the
# cache (see AiAgents::Prompt). Older models cache prompt prefixes by themselves.
class AiAgents::Responder
  class Error < StandardError; end

  Result = Struct.new(:reply, :kind, :language, :entry_keys, :page_ids, :grounded, :tool_calls, :usage, keyword_init: true)

  MAX_TOOL_ROUNDS = 3
  TIMEOUT_SECONDS = 45
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  CONTACT_DETAIL_LIMIT = 255
  CORRECTION = 'Your reply was not sent because %<problems>s. Cite in entry_keys and page_ids the knowledge base entries or pages ' \
               "you used, or say you don't have a confirmed answer and offer to pass the question to the team.".freeze

  # The tool calls ({ name:, arguments:, error: }) and the token usage so far, also after an Error
  attr_reader :tool_calls, :usage

  # visitor: { name:, company:, email_known:, browser_language: }, nil for unknown details
  # history: [{ role: 'user' | 'assistant', content: }], oldest first, ending with the visitor's message to reply to
  # executor: called with 'save_contact' or 'hand_off' and the tool arguments, returns the tool result
  def initialize(agent_bot:, visitor:, team_available:, history:, executor:)
    @agent_bot = agent_bot
    @visitor = visitor
    @team_available = team_available
    @history = history
    @executor = executor
    @tool_calls = []
    @tool_rounds = 0
    @usage = { requests: 0, input_tokens: 0, cached_input_tokens: 0, cache_write_tokens: 0, output_tokens: 0 }
  end

  def perform
    raise Error, 'The OpenAI integration of the account is not enabled' if hook.blank?

    context = { role: 'developer', content: prompt.context_message(visitor: @visitor, team_available: @team_available) }
    input = [static_message, context, *@history]
    output = complete(input)
    problems = grounding_problems(output)
    if problems.any?
      input << { role: 'developer', content: format(CORRECTION, problems: problems.join('; ')) }
      output = complete(input)
      problems = grounding_problems(output)
    end
    Result.new(**output, grounded: problems.empty?, tool_calls: @tool_calls, usage: @usage)
  end

  def model
    @model ||= settings.model || MessageTranslations::OpenaiSettings.model(hook)
  end

  private

  def hook
    @hook ||= MessageTranslations::OpenaiSettings.hook_for(@agent_bot.account)
  end

  def settings
    @settings ||= @agent_bot.ai_agent_settings
  end

  def entries
    @entries ||= @agent_bot.knowledge_entries.published.to_a
  end

  def pages
    @pages ||= readable_pages.select(:id, :title, :url).to_a
  end

  # Pages with content, whatever their status: a refresh (pending) or a failed fetch keeps the content of the last fetch
  def readable_pages
    @agent_bot.pages.where.not(content: [nil, ''])
  end

  def prompt
    @prompt ||= AiAgents::Prompt.new(settings: settings, entries: entries, pages: pages)
  end

  def static_message
    @static_message ||= prompt.static_message(explicit_cache: AiAgents::Prompt.explicit_cache?(model))
  end

  # Runs rounds until the model gives its final reply; output items and tool results are appended to the input
  def complete(input)
    loop do
      body = request(input)
      output_items = Array(body['output'])
      calls = output_items.select { |item| item['type'] == 'function_call' }
      input.concat(output_items)
      return parse_output(body) if calls.empty?
      raise Error, 'OpenAI called tools after the last tool round' if @tool_rounds >= MAX_TOOL_ROUNDS

      @tool_rounds += 1
      calls.each { |call| input << { type: 'function_call_output', call_id: call['call_id'], output: run_tool(call).to_json } }
    end
  end

  def request(input)
    response, body = client.create(request_body(input))
    raise Error, body.dig('error', 'message').presence || "OpenAI failed with HTTP #{response.status}" unless response.success?

    add_usage(body)
    body
  rescue MessageTranslations::OpenaiResponsesClient::Error => e
    raise Error, e.message
  end

  # After the last tool round the model can't call tools, so the loop always ends with a reply
  def request_body(input)
    body = {
      model: model,
      input: input,
      tools: AiAgents::Prompt::TOOLS,
      tool_choice: @tool_rounds < MAX_TOOL_ROUNDS ? 'auto' : 'none',
      text: { format: AiAgents::Prompt::OUTPUT_FORMAT },
      store: false,
      # Routes requests with the same static prompt together and accounts their cache use per bot
      prompt_cache_key: "ai-agent-bot-#{@agent_bot.id}"
    }
    body[:prompt_cache_options] = { mode: 'explicit' } if AiAgents::Prompt.explicit_cache?(model)
    MessageTranslations::OpenaiSettings.apply_model_options!(body, hook)
    effort = settings.reasoning_effort
    effort == MessageTranslations::OpenaiSettings::DEFAULT_REASONING_EFFORT ? body.except(:reasoning) : body.merge(reasoning: { effort: effort })
  end

  def client
    @client ||= MessageTranslations::OpenaiResponsesClient.new(api_key: hook.settings['api_key'], timeout: TIMEOUT_SECONDS)
  end

  def add_usage(body)
    usage = body['usage'] || {}
    @usage[:requests] += 1
    @usage[:input_tokens] += usage['input_tokens'].to_i
    @usage[:cached_input_tokens] += usage.dig('input_tokens_details', 'cached_tokens').to_i
    @usage[:cache_write_tokens] += usage.dig('input_tokens_details', 'cache_write_tokens').to_i
    @usage[:output_tokens] += usage['output_tokens'].to_i
  end

  def parse_output(body)
    output = JSON.parse(MessageTranslations::OpenaiResponsesClient.output_text(body).to_s)
    reply = output['reply'].to_s.strip
    raise Error, 'OpenAI returned an empty reply' if reply.empty?

    {
      reply: reply,
      kind: output['kind'],
      # ISO 639-1, also when the model adds a region such as en-US
      language: output['language'].to_s.strip.downcase.split(/[-_]/).first,
      entry_keys: entry_keys(output),
      page_ids: Array(output['page_ids']).map(&:to_i).uniq
    }
  rescue JSON::ParserError => e
    raise Error, "OpenAI returned a reply that is not JSON: #{e.message}"
  rescue MessageTranslations::OpenaiResponsesClient::Error => e
    raise Error, e.message
  end

  # The knowledge base shows keys as #KB-021
  def entry_keys(output)
    Array(output['entry_keys']).map { |key| key.to_s.strip.delete_prefix('#') }.uniq
  end

  def grounding_problems(output)
    unknown_keys = output[:entry_keys] - entries.map(&:key)
    unknown_page_ids = output[:page_ids] - pages.map(&:id)
    [
      ('a reply of kind answer must cite at least one entry or page' if uncited_answer?(output)),
      ("these keys are not in the KNOWLEDGE BASE: #{unknown_keys.join(', ')}" if unknown_keys.any?),
      ("these page ids are not in PAGES: #{unknown_page_ids.join(', ')}" if unknown_page_ids.any?)
    ].compact
  end

  def uncited_answer?(output)
    output[:kind] == 'answer' && output[:entry_keys].empty? && output[:page_ids].empty?
  end

  def run_tool(call)
    arguments = JSON.parse(call['arguments'].to_s)
    result = case call['name']
             when 'open_page' then open_page(arguments)
             when 'save_contact' then save_contact(arguments)
             when 'hand_off' then hand_off(arguments)
             else { error: "There is no tool named #{call['name']}" }
             end
    @tool_calls << { name: call['name'], arguments: arguments, error: result[:error] }.compact
    result
  rescue JSON::ParserError
    { error: 'The arguments are not valid JSON' }
  end

  def open_page(arguments)
    page = readable_pages.find_by(id: arguments['page_id'])
    return { error: 'There is no page with this id. Use an id from PAGES.' } unless page

    { title: page.title, url: page.url, content: page.content }
  end

  def save_contact(arguments)
    details = {
      'name' => arguments['name'].to_s.squish.truncate(CONTACT_DETAIL_LIMIT).presence,
      'company' => arguments['company'].to_s.squish.truncate(CONTACT_DETAIL_LIMIT).presence,
      'email' => arguments['email'].to_s.strip.downcase.presence
    }.compact
    return { error: 'There is nothing to save' } if details.empty?
    return { error: 'The email address is not valid. Ask the visitor to check it.' } if details['email'] && !valid_email?(details['email'])

    @executor.call('save_contact', details)
  end

  def valid_email?(email)
    email.length <= CONTACT_DETAIL_LIMIT && email.match?(EMAIL_FORMAT)
  end

  # A reply hands off once; a second call gets the result of the first
  def hand_off(arguments)
    reason = AiAgents::Prompt::HANDOFF_REASONS.include?(arguments['reason']) ? arguments['reason'] : 'other'
    details = {
      'reason' => reason,
      'summary' => arguments['summary'].to_s.strip.presence,
      'unanswered_question' => arguments['unanswered_question'].to_s.squish.presence
    }
    @hand_off ||= @executor.call('hand_off', details)
  end
end
