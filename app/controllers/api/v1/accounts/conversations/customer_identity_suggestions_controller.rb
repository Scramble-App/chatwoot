class Api::V1::Accounts::Conversations::CustomerIdentitySuggestionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_user!

  def link
    @conversation = CustomerIdentity::ContactLinkService.new(
      conversation: @conversation,
      user: Current.user
    ).perform

    render 'api/v1/accounts/conversations/show'
  rescue CustomerIdentity::ContactLinkService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def dismiss
    @conversation = CustomerIdentity::SuggestionDismissalService.new(
      conversation: @conversation,
      user: Current.user
    ).perform

    render 'api/v1/accounts/conversations/show'
  rescue CustomerIdentity::SuggestionDismissalService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_user!
    return if Current.user.present?

    render json: { error: 'Only agents can manage customer identity suggestions' }, status: :forbidden
  end
end
