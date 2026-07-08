class CreateConversationAssignmentEvents < ActiveRecord::Migration[7.1]
  def change
    create_assignment_events_table
    add_assignment_event_foreign_keys
    add_assignment_event_indexes
  end

  private

  def create_assignment_events_table
    create_table :conversation_assignment_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :team, foreign_key: true
      t.bigint :from_assignee_id
      t.bigint :to_assignee_id
      t.string :event_type, null: false
      t.string :source, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
  end

  def add_assignment_event_foreign_keys
    add_foreign_key :conversation_assignment_events, :users, column: :from_assignee_id
    add_foreign_key :conversation_assignment_events, :users, column: :to_assignee_id
  end

  def add_assignment_event_indexes
    add_index :conversation_assignment_events, [:conversation_id, :occurred_at], name: 'idx_conversation_assignment_events_on_conversation_time'
    add_index :conversation_assignment_events,
              [:account_id, :to_assignee_id, :occurred_at],
              name: 'idx_conversation_assignment_events_on_account_agent_time'
    add_index :conversation_assignment_events, [:source, :event_type], name: 'idx_conversation_assignment_events_on_source_event_type'
  end
end
