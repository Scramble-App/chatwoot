class AddAgentSchedulesAndTeamReassignment < ActiveRecord::Migration[7.1]
  def change
    add_schedule_columns
    create_account_user_working_hours
    create_account_user_schedule_exceptions
  end

  private

  def add_schedule_columns
    add_column :account_users, :schedule_enabled, :boolean, default: false, null: false
    add_column :account_users, :schedule_timezone, :string

    add_column :teams, :reassign_on_shift_end, :boolean, default: false, null: false
    add_column :team_members, :team_lead, :boolean, default: false, null: false
  end

  def create_account_user_working_hours
    create_table :account_user_working_hours do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.integer :open_hour, null: false
      t.integer :open_minutes, null: false, default: 0
      t.integer :close_hour, null: false
      t.integer :close_minutes, null: false, default: 0

      t.timestamps
    end

    add_index :account_user_working_hours, [:account_user_id, :day_of_week], name: 'idx_account_user_working_hours_on_user_and_day'
  end

  def create_account_user_schedule_exceptions
    create_table :account_user_schedule_exceptions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :available, default: false, null: false
      t.string :name

      t.timestamps
    end

    add_index :account_user_schedule_exceptions, [:account_user_id, :starts_at, :ends_at], name: 'idx_account_user_schedule_exceptions_on_range'
  end
end
