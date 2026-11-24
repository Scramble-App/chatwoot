# == Schema Information
#
# Table name: agent_bot_knowledge_entries
#
#  id                    :bigint           not null, primary key
#  alternative_questions :text
#  answer                :text
#  asked_count           :integer          default(0), not null
#  category              :string
#  frequency             :string
#  key                   :string           not null
#  last_asked_at         :datetime
#  question              :text             not null
#  selling_point         :text
#  short_answer          :text
#  status                :integer          default("draft"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  agent_bot_id          :bigint           not null
#
# Indexes
#
#  index_agent_bot_knowledge_entries_on_account_id               (account_id)
#  index_agent_bot_knowledge_entries_on_agent_bot_id_and_key     (agent_bot_id,key) UNIQUE
#  index_agent_bot_knowledge_entries_on_agent_bot_id_and_status  (agent_bot_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (agent_bot_id => agent_bots.id) ON DELETE => cascade
#
# An entry of the knowledge base of an AI agent bot. Only published entries are given to the model.
# A blank key gets the next KB-NNN number of the bot: one more than its highest KB- number, at least 3 digits.
class AgentBotKnowledgeEntry < ApplicationRecord
  KEY_NUMBER_SQL = "CAST(SUBSTRING(key FROM '^KB-([0-9]+)$') AS numeric)".freeze
  SHORT_TEXT_LIMIT = 255
  QUESTION_LIMIT = 2_000
  TEXT_LIMIT = 10_000

  belongs_to :account
  belongs_to :agent_bot
  has_many :questions, class_name: 'AgentBotKnowledgeQuestion', foreign_key: :knowledge_entry_id,
                       inverse_of: :knowledge_entry, dependent: :delete_all

  enum status: { draft: 0, published: 1, needs_answer: 2 }

  before_validation :ensure_account_id
  before_validation :assign_key, if: -> { key.blank? }

  validates :key, presence: true, uniqueness: { scope: :agent_bot_id }
  validates :key, :category, :frequency, length: { maximum: SHORT_TEXT_LIMIT }
  validates :question, presence: true, length: { maximum: QUESTION_LIMIT }
  validates :alternative_questions, :short_answer, :answer, :selling_point, length: { maximum: TEXT_LIMIT }
  validate :answer_present_when_published

  private

  def ensure_account_id
    self.account_id ||= agent_bot&.account_id
  end

  def assign_key
    return if agent_bot_id.nil?

    last_number = self.class.where(agent_bot_id: agent_bot_id).maximum(Arel.sql(KEY_NUMBER_SQL)).to_i
    self.key = format('KB-%03d', last_number + 1)
  end

  def answer_present_when_published
    return unless published? && answer.blank? && short_answer.blank?

    errors.add(:answer, I18n.t('errors.agent_bot_knowledge_entries.answer.required_to_publish'))
  end
end
