class Internal::RemoveStaleAiGenerationsJob < ApplicationJob
  queue_as :housekeeping

  RETENTION = 7.days

  MODELS = [
    AiGenerations::Summary,
    AiGenerations::KnowledgeAnswer,
    AiGenerations::PreparedReply
  ].freeze

  def perform
    MODELS.each do |model|
      model.where(updated_at: ...RETENTION.ago).in_batches(&:delete_all)
    end
  end
end
