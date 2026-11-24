# Fetches every page of every AI agent bot again. The pages keep their status meanwhile, so the agent keeps using them.
class AgentBotPages::RefreshAllJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    AgentBotPage.where(agent_bot: AgentBot.ai_agent).find_each { |page| AgentBotPages::FetchJob.perform_later(page) }
  end
end
