# == Schema Information
#
# Table name: message_translations
#
#  id            :bigint           not null, primary key
#  content       :text
#  error_message :text
#  model         :string
#  provider      :string           default("openai"), not null
#  status        :integer          default("pending"), not null
#  target_locale :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer          not null
#  message_id    :integer          not null
#
# Indexes
#
#  index_message_translations_on_account_id                    (account_id)
#  index_message_translations_on_account_id_and_target_locale  (account_id,target_locale)
#  index_message_translations_on_message_id                    (message_id)
#  index_message_translations_on_message_locale_provider       (message_id,target_locale,provider) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (message_id => messages.id)
#
class MessageTranslation < ApplicationRecord
  PROVIDER_OPENAI = 'openai'.freeze

  enum status: { pending: 0, completed: 1, failed: 2 }

  belongs_to :account
  belongs_to :message

  validates :provider, presence: true
  validates :target_locale, presence: true, length: { maximum: 20 }
  validates :content, length: { maximum: 150_000 }, allow_blank: true
  validates :error_message, length: { maximum: 10_000 }, allow_blank: true
  validates :message_id, uniqueness: { scope: [:target_locale, :provider] }

  def push_event_data
    {
      id: id,
      message_id: message_id,
      locale: target_locale,
      content: content,
      provider: provider,
      model: model,
      status: status,
      updated_at: updated_at.to_i
    }
  end
end
