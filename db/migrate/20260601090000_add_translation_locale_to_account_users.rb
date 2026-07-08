class AddTranslationLocaleToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :translation_locale, :string
  end
end
