json.extract! resource, :id, :key, :category, :frequency, :question, :alternative_questions, :short_answer, :answer,
              :selling_point, :status, :asked_count
json.last_asked_at resource.last_asked_at&.to_i
json.updated_at resource.updated_at.to_i
