class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create, :ai_agent_defaults, :knowledge_bases]

  def index
    @agent_bots = AgentBot.accessible_to(Current.account)
  end

  # A blank setting of an AI agent bot means its default; the model defaults to the one of the OpenAI integration
  def ai_agent_defaults
    hook = MessageTranslations::OpenaiSettings.hook_for(Current.account)
    @defaults = AiAgents::Settings.defaults.merge(model: hook && MessageTranslations::OpenaiSettings.model(hook))
  end

  # The AI agent bots whose knowledge base the current user may manage
  def knowledge_bases
    @agent_bots = Current.account.agent_bots.ai_agent.order(:id).select { |agent_bot| policy(agent_bot).manage_knowledge? }
    @needs_answer_counts = AgentBotKnowledgeEntry.needs_answer.where(agent_bot_id: @agent_bots.map(&:id)).group(:agent_bot_id).count
  end

  def show; end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    @agent_bot.update!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  def destroy
    @agent_bot.destroy!
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  def reset_secret
    @agent_bot.reset_secret!
  end

  private

  def agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type, bot_config: {})
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot, params[:avatar_url]) if params[:avatar_url].present?
  end
end
