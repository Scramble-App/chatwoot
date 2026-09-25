# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentSchedules::ShiftReassignmentJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { agent.account_users.find_by!(account_id: account.id) }
  let(:on_shift_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:team) { create(:team, account: account, allow_auto_assign: true, reassign_on_shift_end: true) }

  before do
    account.enable_features('assignment_v2')
    account.save!
    account_user.update!(schedule_enabled: true, schedule_timezone: 'UTC')
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    clear_enqueued_jobs
  end

  after do
    Current.assignment_event_source = nil
  end

  def put_on_shift(user)
    on_shift_account_user = user.account_users.find_by!(account_id: account.id)
    on_shift_account_user.update!(schedule_enabled: true, schedule_timezone: 'UTC')
    create(:account_user_schedule_exception, account_user: on_shift_account_user, available: true,
                                             starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:inbox_member, inbox: inbox, user: user)
    create(:team_member, team: team, user: user)
  end

  context 'when an agent is available' do
    before { put_on_shift(on_shift_agent) }

    it 'moves non-resolved team conversations of the off-shift agent to the available agent' do
      conversations = %i[open pending snoozed].map do |status|
        create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: status)
      end
      resolved_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :resolved)

      expect do
        described_class.perform_now
      end.to change(ConversationAssignmentEvent.where(source: 'shift_end', event_type: 'reassigned'), :count).by(3)

      expect(conversations.map { |conversation| conversation.reload.assignee_id }).to all(eq(on_shift_agent.id))
      expect(resolved_conversation.reload.assignee_id).to eq(agent.id)
      expect(ConversationAssignmentEvent.where(source: 'shift_end').pluck(:from_assignee_id, :to_assignee_id).uniq)
        .to eq([[agent.id, on_shift_agent.id]])
    end

    it 'does not duplicate history when retried' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)

      described_class.perform_now

      expect do
        described_class.perform_now
      end.not_to change(ConversationAssignmentEvent.where(conversation: conversation), :count)
    end

    it 'leaves conversations assigned when team shift reassignment is disabled' do
      team.update!(reassign_on_shift_end: false)
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)

      described_class.perform_now

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'records the handover in the conversation timeline' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)

      described_class.perform_now

      expect(Conversations::ActivityMessageJob).to have_been_enqueued.with(
        conversation,
        hash_including(content: "#{agent.name}'s shift ended, reassigned to #{on_shift_agent.name} by Default Policy")
      )
    end

    it 'does not reassign a conversation that changed while the agent was being picked' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_wrap_original do |original, *args|
        Conversation.find(conversation.id).update!(status: :resolved)
        original.call(*args)
      end

      described_class.perform_now

      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(ConversationAssignmentEvent.where(source: 'shift_end')).to be_empty
    end
  end

  # Conversations created while nobody is on shift stay unassigned (e.g. overnight)
  context 'when an agent comes on shift after conversations were left unassigned' do
    let!(:unassigned_conversations) do
      %i[open pending snoozed].index_with do |status|
        create(:conversation, account: account, inbox: inbox, team: team, assignee: nil, status: status)
      end
    end

    before { put_on_shift(on_shift_agent) }

    it 'assigns them' do
      expect(unassigned_conversations.values.map(&:assignee_id)).to all(be_nil)

      described_class.perform_now

      expect(unassigned_conversations.values.map { |conversation| conversation.reload.assignee_id }).to all(eq(on_shift_agent.id))
    end

    it 'leaves pending conversations of an inbox with an active bot to the bot' do
      create(:agent_bot_inbox, inbox: inbox)

      described_class.perform_now

      expect(unassigned_conversations[:pending].reload.assignee_id).to be_nil
      expect(unassigned_conversations[:open].reload.assignee_id).to eq(on_shift_agent.id)
    end
  end

  context 'when another run holds the lock' do
    before do
      put_on_shift(on_shift_agent)
      Redis::LockManager.new.lock(Redis::Alfred::AGENT_SHIFT_REASSIGNMENT_MUTEX, 1.minute)
    end

    after { Redis::LockManager.new.unlock(Redis::Alfred::AGENT_SHIFT_REASSIGNMENT_MUTEX) }

    it 'skips the run' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)

      described_class.perform_now

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end
  end

  context 'when nobody is available' do
    it 'keeps conversations with the off-shift agent' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)

      expect do
        described_class.perform_now
      end.not_to change(ConversationAssignmentEvent, :count)

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end
  end
end
