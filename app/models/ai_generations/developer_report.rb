class AiGenerations::DeveloperReport < ApplicationRecord
  self.table_name = 'ai_generation_developer_reports'

  include AiGeneratable
end
