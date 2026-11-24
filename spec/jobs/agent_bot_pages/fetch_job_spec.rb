require 'rails_helper'

RSpec.describe AgentBotPages::FetchJob do
  it 'runs on the low queue' do
    expect(described_class.new.queue_name).to eq('low')
  end

  it 'fetches the page' do
    page = create(:agent_bot_page)
    service = instance_double(AgentBotPages::FetchService, perform: true)
    allow(AgentBotPages::FetchService).to receive(:new).with(page: page).and_return(service)

    described_class.perform_now(page)

    expect(service).to have_received(:perform)
  end
end
