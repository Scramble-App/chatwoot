# == Schema Information
#
# Table name: agent_bots
#
#  id           :bigint           not null, primary key
#  bot_config   :jsonb
#  bot_type     :integer          default("webhook")
#  description  :string
#  name         :string
#  outgoing_url :string
#  secret       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint
#
# Indexes
#
#  index_agent_bots_on_account_id  (account_id)
#

class AgentBot < ApplicationRecord
  include AccessTokenable
  include Avatarable

  include WebhookSecretable

  scope :accessible_to, lambda { |account|
    account_id = account&.id
    where(account_id: [nil, account_id])
  }

  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :agent_bot_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :platform_app_permissibles, as: :permissible, dependent: :destroy
  has_many :assigned_conversations, class_name: 'Conversation',
                                    foreign_key: :assignee_agent_bot_id,
                                    dependent: :nullify,
                                    inverse_of: :assignee_agent_bot
  # The knowledge base and pages of an AI agent bot
  has_many :knowledge_entries, class_name: 'AgentBotKnowledgeEntry', dependent: :delete_all
  has_many :knowledge_questions, class_name: 'AgentBotKnowledgeQuestion', dependent: :delete_all
  has_many :pages, class_name: 'AgentBotPage', dependent: :delete_all
  belongs_to :account, optional: true
  enum bot_type: { webhook: 0, ai_agent: 1 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validate :validate_ai_agent_settings, if: :ai_agent?

  def ai_agent_settings
    AiAgents::Settings.new(self)
  end

  def available_name
    name
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url || inbox&.avatar_url,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'agent_bot'
    }
  end

  def system_bot?
    account.nil?
  end

  private

  def validate_ai_agent_settings
    ai_agent_settings.validation_errors.each { |message| errors.add(:bot_config, message) }
  end
end

AgentBot.include_mod_with('Audit::AgentBot')
