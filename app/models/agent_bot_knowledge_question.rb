# == Schema Information
#
# Table name: agent_bot_knowledge_questions
#
#  id                 :bigint           not null, primary key
#  content            :text             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_bot_id       :bigint           not null
#  conversation_id    :bigint           not null
#  knowledge_entry_id :bigint           not null
#
# Indexes
#
#  index_agent_bot_knowledge_questions_on_conversation_id     (conversation_id)
#  index_agent_bot_knowledge_questions_on_knowledge_entry_id  (knowledge_entry_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (agent_bot_id => agent_bots.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (knowledge_entry_id => agent_bot_knowledge_entries.id) ON DELETE => cascade
#
# A customer's own wording of a question the AI agent could not answer, attached to a needs_answer entry.
class AgentBotKnowledgeQuestion < ApplicationRecord
  CONTENT_LIMIT = 2_000

  belongs_to :account
  belongs_to :agent_bot
  belongs_to :knowledge_entry, class_name: 'AgentBotKnowledgeEntry', inverse_of: :questions
  belongs_to :conversation

  before_validation :ensure_bot_and_account

  validates :content, presence: true, length: { maximum: CONTENT_LIMIT }

  private

  def ensure_bot_and_account
    self.agent_bot_id ||= knowledge_entry&.agent_bot_id
    self.account_id ||= agent_bot&.account_id
  end
end
