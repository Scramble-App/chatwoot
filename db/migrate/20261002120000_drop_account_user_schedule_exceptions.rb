class DropAccountUserScheduleExceptions < ActiveRecord::Migration[7.1]
  def change
    drop_table :account_user_schedule_exceptions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :available, default: false, null: false
      t.string :name

      t.timestamps

      t.index [:account_user_id, :starts_at, :ends_at], name: 'idx_account_user_schedule_exceptions_on_range'
    end
  end
end
