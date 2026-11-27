require 'rails_helper'

RSpec.describe AgentBotPages::RefreshAllJob do
  it 'runs on the scheduled jobs queue' do
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end

  it 'fetches every page of the AI agent bots again and keeps their status meanwhile' do
    pages = [create(:agent_bot_page, status: :fetched), create(:agent_bot_page, status: :failed)]
    webhook_bot_page = create(:agent_bot_page, agent_bot: create(:agent_bot, account: create(:account)))

    described_class.perform_now

    pages.each { |page| expect(AgentBotPages::FetchJob).to have_been_enqueued.with(page) }
    expect(AgentBotPages::FetchJob).not_to have_been_enqueued.with(webhook_bot_page)
    expect(pages.map { |page| page.reload.status }).to eq(%w[fetched failed])
  end
end
