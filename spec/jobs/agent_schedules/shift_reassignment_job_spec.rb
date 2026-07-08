# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentSchedules::ShiftReassignmentJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { agent.account_users.find_by!(account_id: account.id) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:team) { create(:team, account: account, allow_auto_assign: true, reassign_on_shift_end: true) }

  before do
    account_user.update!(schedule_enabled: true, schedule_timezone: 'UTC')
    create(:team_member, team: team, user: agent)
    clear_enqueued_jobs
  end

  after do
    Current.assignment_event_source = nil
  end

  it 'unassigns non-resolved team conversations when the agent is off shift' do
    open_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :open)
    pending_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :pending)
    snoozed_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :snoozed)
    resolved_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :resolved)

    expect do
      described_class.perform_now
    end.to change(ConversationAssignmentEvent.where(source: 'shift_end'), :count).by(3)

    expect(AutoAssignment::AssignmentJob)
      .to have_been_enqueued.with(inbox_id: inbox.id, statuses: %w[open pending snoozed])

    expect(open_conversation.reload.assignee_id).to be_nil
    expect(pending_conversation.reload.assignee_id).to be_nil
    expect(snoozed_conversation.reload.assignee_id).to be_nil
    expect(resolved_conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'does not duplicate history when retried after conversations are already unassigned' do
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
end
