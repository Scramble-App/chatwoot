class CreateAiGenerationTables < ActiveRecord::Migration[7.1]
  TABLES = %i[ai_generation_summaries ai_generation_knowledge_answers ai_generation_prepared_replies].freeze

  def change
    TABLES.each do |table_name|
      create_table table_name do |t|
        t.references :account, null: false, foreign_key: true, index: true
        t.references :conversation, null: false, foreign_key: true, index: false
        t.references :user, null: false, foreign_key: true, index: false
        t.integer :status, null: false, default: 0
        t.text :content
        t.text :error_message
        t.string :provider, null: false, default: 'openai'
        t.text :source_content if table_name == :ai_generation_prepared_replies

        t.timestamps
      end

      add_index table_name, [:conversation_id, :user_id], unique: true
    end
  end
end
