FactoryBot.define do
  factory :ai_generation_summary, class: 'AiGenerations::Summary' do
    account
    conversation { association :conversation, account: account }
    user { association :user, account: account }
  end

  factory :ai_generation_knowledge_answer, class: 'AiGenerations::KnowledgeAnswer' do
    account
    conversation { association :conversation, account: account }
    user { association :user, account: account }
  end

  factory :ai_generation_developer_report, class: 'AiGenerations::DeveloperReport' do
    account
    conversation { association :conversation, account: account }
    user { association :user, account: account }
  end

  factory :ai_generation_prepared_reply, class: 'AiGenerations::PreparedReply' do
    account
    conversation { association :conversation, account: account }
    user { association :user, account: account }
    source_content { 'draft text' }
  end
end
