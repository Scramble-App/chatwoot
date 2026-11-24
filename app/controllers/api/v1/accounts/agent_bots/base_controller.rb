class Api::V1::Accounts::AgentBots::BaseController < Api::V1::Accounts::BaseController
  before_action :agent_bot

  private

  # Only the AI agent bots of the account have a knowledge base and pages
  def agent_bot
    @agent_bot = Current.account.agent_bots.ai_agent.find(params[:agent_bot_id])
  end
end
