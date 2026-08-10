class AiGenerations::Summary < ApplicationRecord
  self.table_name = 'ai_generation_summaries'

  include AiGeneratable
end
