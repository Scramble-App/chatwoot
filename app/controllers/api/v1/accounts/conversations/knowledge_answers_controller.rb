class Api::V1::Accounts::Conversations::KnowledgeAnswersController < Api::V1::Accounts::Conversations::BaseController
  include AiGeneratableEndpoint

  private

  def generation_model
    AiGenerations::KnowledgeAnswer
  end

  def generation_job
    AiGenerations::KnowledgeAnswerJob
  end
end
