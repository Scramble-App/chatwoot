require 'rails_helper'

RSpec.describe AgentBotPage do
  let(:agent_bot) { create(:agent_bot, :ai_agent) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot) }
  end

  describe 'validations' do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, fetched: 1, failed: 2) }

    it 'starts as pending' do
      expect(described_class.new).to be_pending
    end

    it 'takes the account from the bot when blank' do
      page = create(:agent_bot_page, agent_bot: agent_bot, account: nil)

      expect(page.account).to eq(agent_bot.account)
    end

    it 'keeps up to 30,000 characters of content' do
      expect(build(:agent_bot_page, agent_bot: agent_bot, content: 'a' * 30_000)).to be_valid
      expect(build(:agent_bot_page, agent_bot: agent_bot, content: 'a' * 30_001)).not_to be_valid
    end
  end

  describe 'url' do
    it 'accepts http and https links' do
      expect(build(:agent_bot_page, agent_bot: agent_bot, url: 'http://example.com/pricing')).to be_valid
      expect(build(:agent_bot_page, agent_bot: agent_bot, url: 'https://example.com/faq?lang=en#fees')).to be_valid
    end

    it 'rejects other links' do
      invalid_urls = ['', 'ftp://example.com/file', 'javascript:void(0)', 'mailto:team@example.com', '/founders',
                      'example.com/faq', 'https://', 'https://example.com/ünïcode', 'not a link']

      invalid_urls.each do |url|
        page = build(:agent_bot_page, agent_bot: agent_bot, url: url)

        expect(page).not_to be_valid, "expected #{url.inspect} to be rejected"
      end
    end

    it 'accepts up to 2,048 characters' do
      url = "https://example.com/#{'a' * (Limits::URL_LENGTH_LIMIT - 20)}"

      expect(build(:agent_bot_page, agent_bot: agent_bot, url: url)).to be_valid
      expect(build(:agent_bot_page, agent_bot: agent_bot, url: "#{url}a")).not_to be_valid
    end

    it 'is unique per bot' do
      create(:agent_bot_page, agent_bot: agent_bot, url: 'https://example.com/faq')

      expect(build(:agent_bot_page, agent_bot: agent_bot, url: 'https://example.com/faq')).not_to be_valid
      expect(build(:agent_bot_page, url: 'https://example.com/faq')).to be_valid
    end
  end

  describe 'pages limit' do
    before { create_list(:agent_bot_page, 50, agent_bot: agent_bot) }

    it 'allows at most 50 pages per bot' do
      page = build(:agent_bot_page, agent_bot: agent_bot)

      expect(page).not_to be_valid
      expect(page.errors.full_messages).to eq(['A bot can have at most 50 pages'])
    end

    it 'still updates the pages of a full bot and adds pages to other bots' do
      expect(agent_bot.pages.first.update(title: 'Pricing', status: :fetched)).to be(true)
      expect(build(:agent_bot_page)).to be_valid
    end
  end
end
