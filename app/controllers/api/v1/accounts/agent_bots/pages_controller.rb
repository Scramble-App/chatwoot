class Api::V1::Accounts::AgentBots::PagesController < Api::V1::Accounts::AgentBots::BaseController
  # The pages are bot settings, so only administrators manage them
  before_action -> { authorize @agent_bot, :update? }
  before_action :page, only: [:destroy, :refresh]

  def index
    @pages = @agent_bot.pages.order(:id)
  end

  def create
    @page = @agent_bot.pages.create!(url: params[:url].to_s.strip)
    AgentBotPages::FetchJob.perform_later(@page)
  end

  def destroy
    @page.destroy!
    head :ok
  end

  # The page keeps its content until the fetch replaces it
  def refresh
    @page.pending!
    AgentBotPages::FetchJob.perform_later(@page)
  end

  private

  def page
    @page = @agent_bot.pages.find(params[:id])
  end
end
