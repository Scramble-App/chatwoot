FactoryBot.define do
  factory :agent_bot_page do
    agent_bot factory: [:agent_bot, :ai_agent]
    account { agent_bot.account }
    sequence(:url) { |n| "https://example.com/page-#{n}" }
  end
end
