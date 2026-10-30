class CreateAiGenerationDeveloperReports < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_generation_developer_reports do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.integer :status, null: false, default: 0
      t.text :content
      t.text :error_message
      t.string :provider, null: false, default: 'openai'

      t.timestamps
    end

    add_index :ai_generation_developer_reports, [:conversation_id, :user_id], unique: true
  end
end
