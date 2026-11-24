require 'rails_helper'

RSpec.describe 'Agent bot pages API', type: :request do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: { handoff_team_id: team.id }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pages_url) { "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/pages" }

  describe 'access' do
    let!(:page) { create(:agent_bot_page, agent_bot: agent_bot, status: :fetched) }

    def request_every_endpoint(url, headers)
      [
        -> { get url, headers: headers, as: :json },
        -> { post url, headers: headers, params: { url: 'https://example.com/new' }, as: :json },
        -> { delete "#{url}/#{page.id}", headers: headers, as: :json },
        -> { post "#{url}/#{page.id}/refresh", headers: headers, as: :json }
      ].map do |request|
        request.call
        response.status
      end
    end

    it 'rejects an unauthenticated user' do
      expect(request_every_endpoint(pages_url, {})).to all(eq(401))
    end

    it 'rejects agents, even of the handoff team, and changes nothing' do
      team_agent = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: team_agent)

      expect(request_every_endpoint(pages_url, team_agent.create_new_auth_token)).to all(eq(401))
      expect(agent_bot.pages.pluck(:id, :status)).to eq([[page.id, 'fetched']])
      expect(AgentBotPages::FetchJob).not_to have_been_enqueued
    end

    it 'does not find a bot of another account' do
      other_bot = create(:agent_bot, :ai_agent)
      create(:agent_bot_page, agent_bot: other_bot)

      expect(request_every_endpoint("/api/v1/accounts/#{account.id}/agent_bots/#{other_bot.id}/pages", admin.create_new_auth_token))
        .to all(eq(404))
      expect(other_bot.pages.count).to eq(1)
    end

    it 'does not find a webhook bot' do
      webhook_bot = create(:agent_bot, account: account)

      expect(request_every_endpoint("/api/v1/accounts/#{account.id}/agent_bots/#{webhook_bot.id}/pages", admin.create_new_auth_token))
        .to all(eq(404))
    end
  end

  describe 'GET /pages' do
    it 'lists the pages of the bot' do
      page = create(:agent_bot_page, agent_bot: agent_bot, url: 'https://example.com/fees', title: 'Fees', content: 'No fees.',
                                     status: :fetched, fetched_at: Time.zone.at(1_700_000_000))
      failed_page = create(:agent_bot_page, agent_bot: agent_bot, status: :failed, error_message: '404 Not Found')
      create(:agent_bot_page)

      get pages_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        [
          { 'id' => page.id, 'url' => 'https://example.com/fees', 'title' => 'Fees', 'status' => 'fetched', 'error_message' => nil,
            'fetched_at' => 1_700_000_000, 'content_length' => 8 },
          { 'id' => failed_page.id, 'url' => failed_page.url, 'title' => nil, 'status' => 'failed', 'error_message' => '404 Not Found',
            'fetched_at' => nil, 'content_length' => 0 }
        ]
      )
    end
  end

  describe 'POST /pages' do
    it 'adds a pending page and fetches it' do
      post pages_url, headers: admin.create_new_auth_token, params: { url: ' https://example.com/founders ' }, as: :json

      expect(response).to have_http_status(:success)
      page = agent_bot.pages.last
      expect(response.parsed_body).to include('id' => page.id, 'url' => 'https://example.com/founders', 'status' => 'pending')
      expect(page.account).to eq(account)
      expect(AgentBotPages::FetchJob).to have_been_enqueued.with(page)
    end

    it 'returns the validation errors of the page' do
      create(:agent_bot_page, agent_bot: agent_bot, url: 'https://example.com/founders')

      post pages_url, headers: admin.create_new_auth_token, params: { url: 'https://example.com/founders' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('message' => 'Url has already been taken', 'attributes' => ['url'])
      expect(AgentBotPages::FetchJob).not_to have_been_enqueued
    end

    it 'rejects a link that is not http or https' do
      post pages_url, headers: admin.create_new_auth_token, params: { url: 'ftp://example.com/founders' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Url must be an http or https link')
    end
  end

  describe 'DELETE /pages/:id' do
    it 'deletes the page' do
      page = create(:agent_bot_page, agent_bot: agent_bot)

      delete "#{pages_url}/#{page.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AgentBotPage.exists?(page.id)).to be(false)
    end
  end

  describe 'POST /pages/:id/refresh' do
    it 'marks the page pending, keeps its content and fetches it again' do
      page = create(:agent_bot_page, agent_bot: agent_bot, status: :failed, content: 'Old text.', error_message: 'timeout')

      post "#{pages_url}/#{page.id}/refresh", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => page.id, 'status' => 'pending', 'content_length' => 9)
      expect(page.reload).to have_attributes(status: 'pending', content: 'Old text.')
      expect(AgentBotPages::FetchJob).to have_been_enqueued.with(page)
    end

    it 'does not find a page of another bot' do
      other_page = create(:agent_bot_page, agent_bot: create(:agent_bot, :ai_agent, account: account))

      post "#{pages_url}/#{other_page.id}/refresh", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
