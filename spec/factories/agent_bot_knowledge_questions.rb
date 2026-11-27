FactoryBot.define do
  factory :agent_bot_knowledge_question do
    knowledge_entry factory: :agent_bot_knowledge_entry, status: :needs_answer
    agent_bot { knowledge_entry.agent_bot }
    account { knowledge_entry.account }
    conversation { association :conversation, account: account }
    content { 'Is there a sample question here?' }
  end
end
