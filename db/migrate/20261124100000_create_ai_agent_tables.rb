# Every foreign key cascades in the database, so a rollback to a release without these models can still delete
# conversations, bots and accounts.
class CreateAiAgentTables < ActiveRecord::Migration[7.1]
  def change
    create_knowledge_entries
    create_knowledge_questions
    create_pages
  end

  private

  def create_knowledge_entries
    create_table :agent_bot_knowledge_entries do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :agent_bot, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :key, null: false
      t.string :category
      t.string :frequency
      t.text :question, null: false
      t.text :alternative_questions
      t.text :short_answer
      t.text :answer
      t.text :selling_point
      t.integer :status, null: false, default: 0
      t.integer :asked_count, null: false, default: 0
      t.datetime :last_asked_at

      t.timestamps
    end

    add_index :agent_bot_knowledge_entries, [:agent_bot_id, :key], unique: true
    add_index :agent_bot_knowledge_entries, [:agent_bot_id, :status]
  end

  def create_knowledge_questions
    create_table :agent_bot_knowledge_questions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :agent_bot, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :knowledge_entry, null: false, foreign_key: { to_table: :agent_bot_knowledge_entries, on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.text :content, null: false

      t.timestamps
    end
  end

  def create_pages
    create_table :agent_bot_pages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :agent_bot, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :url, null: false
      t.string :title
      t.text :content
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :agent_bot_pages, [:agent_bot_id, :url], unique: true
  end
end
