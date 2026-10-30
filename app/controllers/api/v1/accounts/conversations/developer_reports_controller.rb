class Api::V1::Accounts::Conversations::DeveloperReportsController < Api::V1::Accounts::Conversations::BaseController
  include AiGeneratableEndpoint

  private

  def generation_model
    AiGenerations::DeveloperReport
  end

  def generation_job
    AiGenerations::DeveloperReportJob
  end
end
