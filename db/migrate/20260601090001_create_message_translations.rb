class CreateMessageTranslations < ActiveRecord::Migration[7.1]
  def change
    create_table :message_translations do |t|
      t.references :account, null: false, type: :integer, foreign_key: true
      t.references :message, null: false, type: :integer, foreign_key: true
      t.string :target_locale, null: false
      t.string :provider, null: false, default: 'openai'
      t.string :model
      t.integer :status, null: false, default: 0
      t.text :content
      t.text :error_message

      t.timestamps
    end

    add_index :message_translations, [:message_id, :target_locale, :provider],
              unique: true,
              name: 'index_message_translations_on_message_locale_provider'
    add_index :message_translations, [:account_id, :target_locale]
  end
end
