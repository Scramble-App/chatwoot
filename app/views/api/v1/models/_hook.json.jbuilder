json.id resource.id
json.app_id resource.app_id
json.status resource.enabled?
json.inbox resource.inbox&.slice(:id, :name)
json.account_id resource.account_id
json.hook_type resource.hook_type

if Current.account_user&.administrator?
  json.settings resource.sanitized_settings
  json.sensitive_settings_configured resource.sensitive_settings_configured
  json.reference_id resource.reference_id
end
