class Api::V1::Accounts::Conversations::SummariesController < Api::V1::Accounts::Conversations::BaseController
  include AiGeneratableEndpoint

  private

  def generation_model
    AiGenerations::Summary
  end

  def generation_job
    AiGenerations::SummaryJob
  end
end
