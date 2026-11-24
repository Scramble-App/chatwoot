FactoryBot.define do
  factory :agent_bot_knowledge_entry do
    agent_bot factory: [:agent_bot, :ai_agent]
    account { agent_bot.account }
    sequence(:question) { |n| "How does sample feature #{n} work?" }
    short_answer { 'Sample short answer.' }
    answer { 'Sample detailed answer.' }
    status { :published }
  end
end
