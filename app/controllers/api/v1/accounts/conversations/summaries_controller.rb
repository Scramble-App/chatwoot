class Api::V1::Accounts::Conversations::SummariesController < Api::V1::Accounts::Conversations::BaseController
  def create
    content = ConversationSummaries::SummaryService.new(
      conversation: @conversation,
      user: Current.user
    ).perform

    render json: { content: content }
  rescue ConversationSummaries::SummaryService::Error,
         ConversationSummaries::OpenaiSummaryService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
