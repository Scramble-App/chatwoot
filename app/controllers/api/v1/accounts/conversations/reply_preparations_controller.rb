class Api::V1::Accounts::Conversations::ReplyPreparationsController < Api::V1::Accounts::Conversations::BaseController
  def create
    content = ReplyPreparations::PrepareReplyService.new(
      conversation: @conversation,
      content: params[:content]
    ).perform

    render json: { content: content }
  rescue ReplyPreparations::PrepareReplyService::Error,
         ReplyPreparations::OpenaiPrepareReplyService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
