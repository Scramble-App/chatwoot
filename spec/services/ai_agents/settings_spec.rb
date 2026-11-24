require 'rails_helper'

RSpec.describe AiAgents::Settings do
  let(:account) { create(:account) }
  let(:agent_bot) { build(:agent_bot, :ai_agent, account: account, bot_config: bot_config) }
  let(:settings) { described_class.new(agent_bot) }

  shared_examples 'the default settings' do
    it 'returns the defaults' do
      expect(settings.model).to be_nil
      expect(settings.reasoning_effort).to eq('low')
      expect(settings.tone_of_voice).to eq(AiAgents::Defaults::TONE_OF_VOICE)
      expect(settings.instructions).to eq(AiAgents::Defaults::INSTRUCTIONS)
      expect(settings.handoff_team_id).to be_nil
      expect(settings.max_replies_per_conversation).to eq(30)
      expect(settings.fallback_message).to eq(AiAgents::Defaults::FALLBACK_MESSAGE)
    end
  end

  context 'without a config' do
    let(:bot_config) { nil }

    it_behaves_like 'the default settings'
  end

  context 'with blank values' do
    let(:bot_config) do
      { 'model' => ' ', 'reasoning_effort' => '', 'tone_of_voice' => "\n", 'instructions' => nil, 'handoff_team_id' => '',
        'max_replies_per_conversation' => '', 'fallback_message' => '' }
    end

    it_behaves_like 'the default settings'

    it 'has no handoff team' do
      expect(settings.handoff_team).to be_nil
    end
  end

  context 'with values' do
    let(:team) { create(:team, account: account) }
    let(:bot_config) do
      { model: ' gpt-sample ', reasoning_effort: 'High', tone_of_voice: 'Calm and brief.', instructions: 'Answer in one sentence.',
        handoff_team_id: team.id.to_s, max_replies_per_conversation: '12', fallback_message: 'One moment, please.' }
    end

    it 'returns them, with numbers sent as text cast to integers' do
      expect(settings.model).to eq('gpt-sample')
      expect(settings.reasoning_effort).to eq('high')
      expect(settings.tone_of_voice).to eq('Calm and brief.')
      expect(settings.instructions).to eq('Answer in one sentence.')
      expect(settings.handoff_team_id).to eq(team.id)
      expect(settings.max_replies_per_conversation).to eq(12)
      expect(settings.fallback_message).to eq('One moment, please.')
    end

    it 'finds the handoff team in the account of the bot' do
      expect(settings.handoff_team).to eq(team)
    end
  end

  context 'with a handoff team that was deleted' do
    let(:bot_config) { { 'handoff_team_id' => create(:team, account: account).tap(&:destroy!).id } }

    it 'has no handoff team' do
      expect(settings.handoff_team).to be_nil
    end
  end

  describe '.defaults' do
    it 'exposes the defaults for the API, without the model of the OpenAI integration' do
      expect(described_class.defaults).to eq(
        reasoning_effort: 'low',
        tone_of_voice: AiAgents::Defaults::TONE_OF_VOICE,
        instructions: AiAgents::Defaults::INSTRUCTIONS,
        max_replies_per_conversation: 30,
        fallback_message: AiAgents::Defaults::FALLBACK_MESSAGE
      )
    end
  end
end
