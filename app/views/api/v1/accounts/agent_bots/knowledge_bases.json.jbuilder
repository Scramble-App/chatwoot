json.array! @agent_bots do |agent_bot|
  json.id agent_bot.id
  json.name agent_bot.name
  json.thumbnail agent_bot.avatar_url
  json.needs_answer_count @needs_answer_counts.fetch(agent_bot.id, 0)
end
