json.extract! resource, :id, :url, :title, :status, :error_message
json.fetched_at resource.fetched_at&.to_i
json.content_length resource.content.to_s.length
