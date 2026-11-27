require 'rails_helper'
require Rails.root.join 'spec/models/concerns/access_tokenable_shared.rb'
require Rails.root.join 'spec/models/concerns/avatarable_shared.rb'

RSpec.describe AgentBot do
  describe 'associations' do
    it { is_expected.to have_many(:agent_bot_inboxes) }
    it { is_expected.to have_many(:inboxes) }
    it { is_expected.to have_many(:platform_app_permissibles) }
    it { is_expected.to have_many(:knowledge_entries).class_name('AgentBotKnowledgeEntry').dependent(:delete_all) }
    it { is_expected.to have_many(:knowledge_questions).class_name('AgentBotKnowledgeQuestion').dependent(:delete_all) }
    it { is_expected.to have_many(:pages).class_name('AgentBotPage').dependent(:delete_all) }
  end

  it { is_expected.to define_enum_for(:bot_type).with_values(webhook: 0, ai_agent: 1) }

  describe 'concerns' do
    it_behaves_like 'access_tokenable'
    it_behaves_like 'avatarable'
  end

  context 'when it validates outgoing_url length' do
    let(:agent_bot) { create(:agent_bot) }

    it 'valid when within limit' do
      agent_bot.outgoing_url = 'a' * Limits::URL_LENGTH_LIMIT
      expect(agent_bot.valid?).to be true
    end

    it 'invalid when crossed the limit' do
      agent_bot.outgoing_url = 'a' * (Limits::URL_LENGTH_LIMIT + 1)
      agent_bot.valid?
      expect(agent_bot.errors[:outgoing_url]).to include("is too long (maximum is #{Limits::URL_LENGTH_LIMIT} characters)")
    end
  end

  context 'when agent bot is deleted' do
    let(:agent_bot) { create(:agent_bot) }
    let(:message) { create(:message, sender: agent_bot) }

    it 'nullifies the message sender key' do
      expect(message.sender).to eq agent_bot
      agent_bot.destroy!

      expect(message.reload.sender).to be_nil
    end

    it 'destroys associated platform_app_permissibles' do
      platform_app = create(:platform_app)
      create(:platform_app_permissible, platform_app: platform_app, permissible: agent_bot)

      expect { agent_bot.destroy! }.to change(PlatformAppPermissible, :count).by(-1)
    end

    context 'with a knowledge base and pages' do
      let(:agent_bot) { create(:agent_bot, :ai_agent) }

      before do
        entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer)
        create(:agent_bot_knowledge_question, knowledge_entry: entry)
        create(:agent_bot_page, agent_bot: agent_bot)
      end

      def remaining_rows
        [AgentBotKnowledgeEntry, AgentBotKnowledgeQuestion, AgentBotPage].map { |model| model.where(agent_bot_id: agent_bot.id).count }
      end

      it 'deletes its entries, questions and pages' do
        other_page = create(:agent_bot_page)
        expect(remaining_rows).to eq([1, 1, 1])

        agent_bot.destroy!

        expect(remaining_rows).to eq([0, 0, 0])
        expect(AgentBotPage.exists?(other_page.id)).to be(true)
      end

      # A release without these models deletes bots and accounts without knowing about the tables
      it 'leaves no rows when the database deletes the bot directly' do
        described_class.where(id: agent_bot.id).delete_all

        expect(remaining_rows).to eq([0, 0, 0])
      end

      it 'leaves no rows when the database deletes the account directly' do
        Account.where(id: agent_bot.account_id).delete_all

        expect(remaining_rows).to eq([0, 0, 0])
      end
    end
  end

  describe 'ai_agent settings validation' do
    let(:account) { create(:account) }
    let(:agent_bot) { build(:agent_bot, :ai_agent, account: account) }

    def errors_for(bot_config)
      agent_bot.bot_config = bot_config
      agent_bot.valid?
      agent_bot.errors[:bot_config]
    end

    it 'accepts a blank config' do
      expect(errors_for({})).to be_empty
      expect(errors_for(nil)).to be_empty
    end

    it 'accepts every setting' do
      bot_config = {
        model: 'gpt-sample', reasoning_effort: 'Medium', tone_of_voice: 'a' * 5_000, instructions: 'a' * 10_000,
        handoff_team_id: create(:team, account: account).id, max_replies_per_conversation: 200, fallback_message: 'a' * 1_000
      }

      expect(errors_for(bot_config)).to be_empty
    end

    it 'accepts blank values and numbers sent as form data' do
      bot_config = { 'model' => '', 'reasoning_effort' => ' ', 'tone_of_voice' => '', 'instructions' => nil,
                     'handoff_team_id' => create(:team, account: account).id.to_s, 'max_replies_per_conversation' => '1',
                     'fallback_message' => '' }

      expect(errors_for(bot_config)).to be_empty
      expect(errors_for({ 'handoff_team_id' => '', 'max_replies_per_conversation' => '' })).to be_empty
    end

    it 'rejects unknown keys' do
      expect(errors_for({ 'tone_of_voice' => 'Calm', 'webhook_url' => 'https://example.com', 'temperature' => 1 }))
        .to eq(['has unknown keys: webhook_url, temperature'])
    end

    it 'rejects texts over their limits or that are not text' do
      bot_config = { 'model' => 'a' * 256, 'tone_of_voice' => 'a' * 5_001, 'instructions' => 'a' * 10_001,
                     'fallback_message' => ['Sorry'] }

      expect(errors_for(bot_config)).to contain_exactly(
        'model must be text of at most 255 characters',
        'tone_of_voice must be text of at most 5000 characters',
        'instructions must be text of at most 10000 characters',
        'fallback_message must be text of at most 1000 characters'
      )
    end

    it 'rejects a reasoning effort the OpenAI settings would not accept' do
      expect(errors_for({ 'reasoning_effort' => 'very high' })).to eq(['reasoning_effort is invalid'])
      expect(errors_for({ 'reasoning_effort' => 'x_high' })).to be_empty
    end

    it 'rejects a reply limit that is not a whole number from 1 to 200' do
      [0, 201, '-5', 'many', 2.5].each do |limit|
        expect(errors_for({ 'max_replies_per_conversation' => limit }))
          .to eq(['max_replies_per_conversation must be a whole number from 1 to 200']), "expected #{limit.inspect} to be rejected"
      end
    end

    it 'rejects a handoff team of another account or one that does not exist' do
      [create(:team).id, 0, 'sales'].each do |team_id|
        expect(errors_for({ 'handoff_team_id' => team_id }))
          .to eq(['handoff_team_id must be a team of this account']), "expected #{team_id.inspect} to be rejected"
      end
    end

    it 'shows the errors under the bot config' do
      errors_for({ 'max_replies_per_conversation' => 0 })

      expect(agent_bot.errors.full_messages).to eq(['Bot config max_replies_per_conversation must be a whole number from 1 to 200'])
    end

    it 'stores line breaks sent as CRLF as LF and counts them that way against the limits' do
      tone_of_voice = "#{'a' * 4_998}\r\nb"
      agent_bot.bot_config = { 'tone_of_voice' => tone_of_voice, 'instructions' => "One\rTwo\r\nThree", 'fallback_message' => "Sorry.\r\n" }

      expect(tone_of_voice.length).to eq(5_001)
      expect(agent_bot.save).to be(true)
      expect(agent_bot.reload.bot_config).to eq(
        'tone_of_voice' => "#{'a' * 4_998}\nb", 'instructions' => "One\nTwo\nThree", 'fallback_message' => "Sorry.\n"
      )
    end

    it 'saves other changes of a bot whose handoff team was deleted until its settings change' do
      team = create(:team, account: account)
      bot = create(:agent_bot, :ai_agent, account: account, bot_config: { 'handoff_team_id' => team.id })
      team.destroy!
      bot.reload

      expect(bot.update(name: 'Renamed')).to be(true)
      expect { bot.reset_secret! }.not_to raise_error
      expect(bot.update(bot_config: { 'handoff_team_id' => team.id, 'tone_of_voice' => 'Calm' })).to be(false)
      expect(bot.errors[:bot_config]).to eq(['handoff_team_id must be a team of this account'])
    end

    it 'validates the settings when a webhook bot becomes an AI agent' do
      bot = create(:agent_bot, account: account, bot_config: { 'webhook_url' => 'https://example.com' })

      expect(bot.update(bot_type: :ai_agent)).to be(false)
      expect(bot.errors[:bot_config]).to eq(['has unknown keys: webhook_url'])
    end

    it 'leaves the config of webhook bots alone' do
      webhook_bot = build(:agent_bot, bot_config: { 'webhook_url' => 'https://example.com', 'max_replies_per_conversation' => 0 })

      expect(webhook_bot).to be_valid
    end
  end

  describe '#ai_agent_settings' do
    it 'reads the settings from the bot config' do
      agent_bot = build(:agent_bot, :ai_agent, bot_config: { 'max_replies_per_conversation' => 5 })

      expect(agent_bot.ai_agent_settings).to be_a(AiAgents::Settings)
      expect(agent_bot.ai_agent_settings.max_replies_per_conversation).to eq(5)
    end
  end

  describe '#system_bot?' do
    context 'when account_id is nil' do
      let(:agent_bot) { create(:agent_bot, account_id: nil) }

      it 'returns true' do
        expect(agent_bot.system_bot?).to be true
      end
    end

    context 'when account_id is present' do
      let(:account) { create(:account) }
      let(:agent_bot) { create(:agent_bot, account: account) }

      it 'returns false' do
        expect(agent_bot.system_bot?).to be false
      end
    end
  end
end
