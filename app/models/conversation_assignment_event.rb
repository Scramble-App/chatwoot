# == Schema Information
#
# Table name: conversation_assignment_events
#
#  id               :bigint           not null, primary key
#  actor_type       :string
#  event_type       :string           not null
#  metadata         :jsonb            not null
#  occurred_at      :datetime         not null
#  source           :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  actor_id         :bigint
#  conversation_id  :bigint           not null
#  from_assignee_id :bigint
#  inbox_id         :bigint           not null
#  team_id          :bigint
#  to_assignee_id   :bigint
#
# Indexes
#
#  idx_conversation_assignment_events_on_account_agent_time  (account_id,to_assignee_id,occurred_at)
#  idx_conversation_assignment_events_on_conversation_time   (conversation_id,occurred_at)
#  idx_conversation_assignment_events_on_source_event_type   (source,event_type)
#  index_conversation_assignment_events_on_account_id        (account_id)
#  index_conversation_assignment_events_on_conversation_id   (conversation_id)
#  index_conversation_assignment_events_on_inbox_id          (inbox_id)
#  index_conversation_assignment_events_on_team_id           (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (from_assignee_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (to_assignee_id => users.id)
#
class ConversationAssignmentEvent < ApplicationRecord
  EVENT_TYPES = %w[assigned unassigned reassigned snapshot].freeze
  SOURCES = %w[manual automation auto_assignment shift_end snapshot system].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :team, optional: true
  belongs_to :from_assignee, class_name: 'User', optional: true
  belongs_to :to_assignee, class_name: 'User', optional: true

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :occurred_at, presence: true
end
