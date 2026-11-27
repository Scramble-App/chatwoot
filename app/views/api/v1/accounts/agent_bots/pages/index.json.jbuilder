json.array! @pages do |page|
  json.partial! 'api/v1/models/agent_bot_page', formats: [:json], resource: page
end
