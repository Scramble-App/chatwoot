class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    @agents = agents
  end

  def create
    builder = AgentBuilder.new(
      email: new_agent_params['email'],
      name: new_agent_params['name'],
      role: new_agent_params['role'],
      availability: new_agent_params['availability'],
      auto_offline: new_agent_params['auto_offline'],
      translation_locale: new_agent_params['translation_locale'],
      inviter: current_user,
      account: Current.account
    )

    @agent = builder.perform
  end

  def update
    ActiveRecord::Base.transaction do
      @agent.update!(agent_params.slice(:name).compact)
      @agent.current_account_user.update!(account_user_params)
      update_agent_schedule(@agent.current_account_user)
    end
  end

  def destroy
    @agent.current_account_user.destroy!
    delete_user_record(@agent)
    head :ok
  end

  def bulk_create
    emails = params[:emails]

    emails.each do |email|
      builder = AgentBuilder.new(
        email: email,
        name: email.split('@').first,
        inviter: current_user,
        account: Current.account
      )
      begin
        builder.perform
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.info "[Agent#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
      end
    end

    # This endpoint is used to bulk create agents during onboarding
    # onboarding_step key in present in Current account custom attributes, since this is a one time operation
    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
    head :ok
  end

  private

  def check_authorization
    return if action_name == 'update' && team_lead_schedule_update?

    super(User)
  end

  def fetch_agent
    @agent = agents.find(params[:id])
  end

  def account_user_attributes
    [:role, :availability, :auto_offline, :translation_locale, :schedule_enabled, :schedule_timezone]
  end

  def allowed_agent_params
    [
      :name, :email, :role, :availability, :auto_offline, :translation_locale, :schedule_enabled, :schedule_timezone,
      { working_hours: [:day_of_week, :open_hour, :open_minutes, :close_hour, :close_minutes],
        schedule_exceptions: [:starts_at, :ends_at, :available, :name] }
    ]
  end

  def agent_params
    params.require(:agent).permit(allowed_agent_params)
  end

  def account_user_params
    attributes = agent_params.slice(*account_user_attributes).compact
    attributes[:translation_locale] = agent_params[:translation_locale] if agent_params.key?(:translation_locale)
    attributes
  end

  def new_agent_params
    params.require(:agent).permit(:email, :name, :role, :availability, :auto_offline, :translation_locale, :schedule_enabled, :schedule_timezone)
  end

  def agents
    @agents ||= Current.account.users.order_by_full_name.includes(:account_users, { avatar_attachment: [:blob] })
  end

  def validate_limit_for_bulk_create
    limit_available = params[:emails].count <= available_agent_count

    render_payment_required('Account limit exceeded. Please purchase more licenses') unless limit_available
  end

  def validate_limit
    render_payment_required('Account limit exceeded. Please purchase more licenses') unless can_add_agent?
  end

  def available_agent_count
    Current.account.usage_limits[:agents] - agents.count
  end

  def can_add_agent?
    available_agent_count.positive?
  end

  def delete_user_record(agent)
    DeleteObjectJob.perform_later(agent) if agent.reload.account_users.blank?
  end

  def update_agent_schedule(account_user)
    update_working_hours(account_user) if agent_params.key?(:working_hours)
    update_schedule_exceptions(account_user) if agent_params.key?(:schedule_exceptions)
  end

  def update_working_hours(account_user)
    account_user.working_hours.destroy_all
    Array(agent_params[:working_hours]).each do |working_hour|
      account_user.working_hours.create!(working_hour.to_h)
    end
  end

  def update_schedule_exceptions(account_user)
    account_user.schedule_exceptions.destroy_all
    Array(agent_params[:schedule_exceptions]).each do |schedule_exception|
      account_user.schedule_exceptions.create!(schedule_exception.to_h)
    end
  end

  def team_lead_schedule_update?
    return false if Current.account_user.administrator?
    return false unless schedule_update_only?

    team_members = Current.account_user.user.team_members
    lead_team_ids = team_members
                    .team_leads
                    .joins(:team)
                    .where(teams: { account_id: Current.account.id })
                    .select(:team_id)
    TeamMember.exists?(team_id: lead_team_ids, user_id: @agent.id)
  end

  def schedule_update_only?
    keys = agent_params.keys.map(&:to_s)
    keys.present? && (keys - %w[schedule_enabled schedule_timezone working_hours schedule_exceptions]).empty?
  end
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
