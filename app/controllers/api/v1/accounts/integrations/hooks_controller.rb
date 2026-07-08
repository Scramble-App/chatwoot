class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization

  def create
    @hook = Current.account.hooks.create!(permitted_params)
  end

  def update
    @hook.update!(permitted_update_params)
  end

  def process_event
    response = @hook.process_event(params[:event])

    # for cases like an invalid event, or when conversation does not have enough messages
    # for a label suggestion, the response is nil
    if response.nil?
      render json: { message: nil }
    elsif response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { message: response[:message] }
    end
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def check_authorization
    authorize(:hook)
  end

  def permitted_params
    params.require(:hook).permit(:app_id, :inbox_id, :status, settings: {})
  end

  def permitted_update_params
    hook_params = permitted_params.slice(:status, :settings)
    return hook_params unless hook_params.key?(:settings)

    hook_params[:settings] = merged_settings_for_update(hook_params[:settings])
    hook_params
  end

  def merged_settings_for_update(incoming_settings)
    incoming = incoming_settings.to_h.deep_stringify_keys
    existing = @hook.settings.to_h.deep_stringify_keys

    @hook.sensitive_properties.each do |property|
      incoming.delete(property) if incoming[property].blank?
    end

    existing.merge(incoming)
  end
end
