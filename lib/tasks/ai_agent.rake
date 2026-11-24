namespace :ai_agent do
  # bundle exec rake "ai_agent:evaluate[BOT_ID]" CASES=cases.yml LIMIT=50 ONLY=phrasings|cases|scenarios CONCURRENCY=2 OUT=report.json
  # SEED picks the LIMIT sample of phrasings (1 by default). INPUT_PRICE_PER_1M, CACHED_INPUT_PRICE_PER_1M and OUTPUT_PRICE_PER_1M
  # (USD per 1M tokens) give the estimated cost. Calls OpenAI with the account's key; writes nothing to the database.
  desc 'Evaluate the replies of an AI agent bot on its knowledge base phrasings and a YAML file of cases and scenarios'
  task :evaluate, [:bot_id] => :environment do |_task, args|
    agent_bot = AgentBot.ai_agent.find(args[:bot_id])
    report = AiAgents::Evaluation.new(
      agent_bot: agent_bot,
      cases_path: ENV.fetch('CASES', nil),
      limit: ENV.fetch('LIMIT', nil),
      only: ENV.fetch('ONLY', nil),
      concurrency: ENV.fetch('CONCURRENCY', nil),
      seed: ENV.fetch('SEED', nil),
      prices: {
        input: ENV.fetch('INPUT_PRICE_PER_1M', nil),
        cached_input: ENV.fetch('CACHED_INPUT_PRICE_PER_1M', nil),
        output: ENV.fetch('OUTPUT_PRICE_PER_1M', nil)
      }
    ).perform { |line| puts line }

    default_out = Rails.root.join("tmp/ai_agent_evaluation_#{agent_bot.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.json").to_s
    out = ENV.fetch('OUT', nil).presence || default_out
    File.write(out, JSON.pretty_generate(report.to_h))
    puts '', report.summary, '', "JSON report: #{out}"
  end
end
