require 'rails_helper'

RSpec.describe AgentBotPolicy, type: :policy do
  subject(:agent_bot_policy) { described_class }

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: { handoff_team_id: team.id }) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:team_agent) { create(:user, account: account).tap { |user| create(:team_member, team: team, user: user) } }

  def context_for(user)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  permissions :ai_agent_defaults?, :knowledge_bases? do
    it 'permits an administrator to read the defaults and the knowledge bases' do
      expect(agent_bot_policy).to permit(context_for(administrator), AgentBot)
    end
  end

  permissions :ai_agent_defaults? do
    it 'rejects an agent, even of a handoff team' do
      expect(agent_bot_policy).not_to permit(context_for(team_agent), AgentBot)
    end
  end

  permissions :knowledge_bases? do
    it 'permits an agent, who sees only the bots of their handoff teams' do
      expect(agent_bot_policy).to permit(context_for(agent), AgentBot)
    end
  end

  permissions :manage_knowledge? do
    it 'permits an administrator without a team' do
      expect(agent_bot_policy).to permit(context_for(administrator), agent_bot)
    end

    it 'permits an agent of the handoff team' do
      expect(agent_bot_policy).to permit(context_for(team_agent), agent_bot)
    end

    it 'rejects an agent of another team' do
      create(:team_member, team: create(:team, account: account), user: agent)

      expect(agent_bot_policy).not_to permit(context_for(agent), agent_bot)
    end

    it 'rejects agents when the bot has no handoff team' do
      agent_bot.update!(bot_config: {})

      expect(agent_bot_policy).not_to permit(context_for(team_agent), agent_bot)
    end

    it 'rejects agents when the handoff team was deleted' do
      context = context_for(team_agent)
      bot = agent_bot
      team.destroy!

      expect(agent_bot_policy).not_to permit(context, bot.reload)
    end
  end
end
