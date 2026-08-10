class AiGenerations::KnowledgeAnswer < ApplicationRecord
  self.table_name = 'ai_generation_knowledge_answers'

  include AiGeneratable
end
