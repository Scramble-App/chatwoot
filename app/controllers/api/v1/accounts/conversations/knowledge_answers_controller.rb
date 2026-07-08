class Api::V1::Accounts::Conversations::KnowledgeAnswersController < Api::V1::Accounts::Conversations::BaseController
  def create
    content = KnowledgeAnswers::AnswerService.new(
      conversation: @conversation,
      user: Current.user
    ).perform

    render json: { content: content }
  rescue KnowledgeAnswers::AnswerService::Error,
         KnowledgeAnswers::OpenaiAnswerService::Error,
         Integrations::OnyxMcp::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
