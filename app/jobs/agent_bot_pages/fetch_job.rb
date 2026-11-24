class AgentBotPages::FetchJob < ApplicationJob
  queue_as :low

  def perform(page)
    AgentBotPages::FetchService.new(page: page).perform
  end
end
