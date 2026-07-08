json.array! @team_members do |team_member|
  json.partial! 'api/v1/models/agent', formats: [:json], resource: team_member.user
  json.team_lead team_member.team_lead
end
