json.partial! 'api/v1/models/agent_bot_knowledge_entry', formats: [:json], resource: @knowledge_entry
json.questions @questions do |question|
  json.id question.id
  json.content question.content
  json.conversation_id question.conversation.display_id
  json.created_at question.created_at.to_i
end
