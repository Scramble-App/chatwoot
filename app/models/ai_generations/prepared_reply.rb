class AiGenerations::PreparedReply < ApplicationRecord
  self.table_name = 'ai_generation_prepared_replies'

  include AiGeneratable
end
