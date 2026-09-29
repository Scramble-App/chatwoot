class Api::V1::Accounts::Conversations::DictationsController < Api::V1::Accounts::Conversations::BaseController
  def create
    text = Dictations::OpenaiTranscriptionService.new(account: Current.account, user: Current.user, audio: params.require(:audio)).perform
    render json: { text: text }
  rescue Dictations::OpenaiTranscriptionService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
