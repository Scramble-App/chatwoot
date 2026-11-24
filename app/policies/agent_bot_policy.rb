class AgentBotPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def reset_access_token?
    @account_user.administrator?
  end

  def reset_secret?
    @account_user.administrator?
  end

  def ai_agent_defaults?
    @account_user.administrator?
  end

  def knowledge_bases?
    @account_user.administrator? || @account_user.agent?
  end

  # The knowledge base of an AI agent bot: administrators, and agents in the bot's handoff team
  def manage_knowledge?
    @account_user.administrator? || handoff_team_member?
  end

  private

  def handoff_team_member?
    team = @record.ai_agent_settings.handoff_team
    team.present? && team.team_members.exists?(user_id: @user.id)
  end
end
