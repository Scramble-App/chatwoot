# Synthetic OpenAI Responses API bodies for the AI agent specs
module AiAgentOpenaiHelpers
  OPENAI_RESPONSES_URL = 'https://api.openai.com/v1/responses'.freeze

  def create_ai_agent_openai_hook(account)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' })
  end

  def openai_usage(input: 100, cached: 40, written: 10, output: 20)
    { input_tokens: input, input_tokens_details: { cached_tokens: cached, cache_write_tokens: written }, output_tokens: output }
  end

  # The final reply: a reasoning item and a message with the JSON output
  def openai_reply(reply: 'Hi, I am Scramble\'s AI assistant.', kind: 'conversation', language: 'en', entry_keys: [], page_ids: [])
    text = { reply: reply, kind: kind, language: language, entry_keys: entry_keys, page_ids: page_ids }.to_json
    {
      id: 'resp_reply', status: 'completed', usage: openai_usage,
      output: [
        { id: 'rs_reply', type: 'reasoning', summary: [], encrypted_content: 'encrypted-reply' },
        { id: 'msg_reply', type: 'message', role: 'assistant', status: 'completed',
          content: [{ type: 'output_text', text: text, annotations: [] }] }
      ]
    }
  end

  # calls: [[name, arguments], ...], one function call each
  def openai_tool_calls(*calls)
    function_calls = calls.map.with_index do |(name, arguments), index|
      { id: "fc_#{index}", type: 'function_call', status: 'completed', call_id: "call_#{name}_#{index}", name: name,
        arguments: arguments.to_json }
    end
    {
      id: 'resp_tools', status: 'completed', usage: openai_usage,
      output: [{ id: 'rs_tools', type: 'reasoning', summary: [], encrypted_content: 'encrypted-tools' }, *function_calls]
    }
  end

  # Answers the requests with the bodies in order (the last one repeats) and returns the parsed request bodies
  def stub_openai_responses(*bodies)
    requests = []
    stub_request(:post, OPENAI_RESPONSES_URL).to_return do |request|
      requests << JSON.parse(request.body)
      { status: 200, body: bodies[[requests.size, bodies.size].min - 1].to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    requests
  end
end
