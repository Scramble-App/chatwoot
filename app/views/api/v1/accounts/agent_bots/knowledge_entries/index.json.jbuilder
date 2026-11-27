json.payload do
  json.array! @knowledge_entries do |knowledge_entry|
    json.partial! 'api/v1/models/agent_bot_knowledge_entry', formats: [:json], resource: knowledge_entry
  end
end

json.meta do
  json.count @knowledge_entries.total_count
  json.current_page @knowledge_entries.current_page
  json.per_page @knowledge_entries.limit_value
  json.categories @categories
  json.status_counts @status_counts
end
