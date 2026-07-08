json.id resource.id
# could be nil for a deleted agent hence the safe operator before account id
json.account_id Current.account&.id
json.availability_status resource.availability_status
json.auto_offline resource.auto_offline
json.availability_source resource.current_account_user&.availability_source
json.schedule_enabled resource.current_account_user&.schedule_enabled?
json.schedule_timezone resource.current_account_user&.schedule_time_zone
json.confirmed resource.confirmed?
json.email resource.email
json.provider resource.provider
json.available_name resource.available_name
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.name resource.name
json.role resource.role
json.translation_locale resource.current_account_user&.translation_locale
json.working_hours do
  json.array! resource.current_account_user&.working_hours || [] do |working_hour|
    json.day_of_week working_hour.day_of_week
    json.open_hour working_hour.open_hour
    json.open_minutes working_hour.open_minutes
    json.close_hour working_hour.close_hour
    json.close_minutes working_hour.close_minutes
  end
end
json.schedule_exceptions do
  json.array! resource.current_account_user&.schedule_exceptions || [] do |schedule_exception|
    json.id schedule_exception.id
    json.starts_at schedule_exception.starts_at
    json.ends_at schedule_exception.ends_at
    json.available schedule_exception.available
    json.name schedule_exception.name
  end
end
json.thumbnail resource.avatar_url
json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
