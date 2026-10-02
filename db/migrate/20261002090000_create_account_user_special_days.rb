class CreateAccountUserSpecialDays < ActiveRecord::Migration[7.1]
  def change
    create_table :account_user_special_days do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.date :date, null: false
      t.boolean :day_off, null: false, default: false
      t.integer :open_hour
      t.integer :open_minutes, null: false, default: 0
      t.integer :close_hour
      t.integer :close_minutes, null: false, default: 0

      t.timestamps
    end

    add_index :account_user_special_days, [:account_user_id, :date], name: 'idx_account_user_special_days_on_user_and_date'
  end
end
