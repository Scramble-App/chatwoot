class Api::V1::Accounts::Conversations::ReplyPreparationsController < Api::V1::Accounts::Conversations::BaseController
  include AiGeneratableEndpoint

  private

  def generation_model
    AiGenerations::PreparedReply
  end

  def generation_job
    AiGenerations::PreparedReplyJob
  end

  def reset_attributes
    { source_content: params[:content] }
  end
end
