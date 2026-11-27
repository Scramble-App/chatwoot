# == Schema Information
#
# Table name: agent_bot_pages
#
#  id            :bigint           not null, primary key
#  content       :text
#  error_message :text
#  fetched_at    :datetime
#  status        :integer          default("pending"), not null
#  title         :string
#  url           :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  agent_bot_id  :bigint           not null
#
# Indexes
#
#  index_agent_bot_pages_on_agent_bot_id_and_url  (agent_bot_id,url) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (agent_bot_id => agent_bots.id) ON DELETE => cascade
#
# A website page an AI agent bot may open for facts, with its extracted main text.
class AgentBotPage < ApplicationRecord
  include UrlHelper

  MAX_PAGES_PER_BOT = 50
  CONTENT_LIMIT = 30_000

  belongs_to :account
  belongs_to :agent_bot

  enum :status, { pending: 0, fetched: 1, failed: 2 }, validate: true

  before_validation :ensure_account_id

  validates :url, presence: true, length: { maximum: Limits::URL_LENGTH_LIMIT }, uniqueness: { scope: :agent_bot_id }
  validates :content, length: { maximum: CONTENT_LIMIT }
  validate :url_is_http
  validate :pages_limit, on: :create

  private

  def ensure_account_id
    self.account_id ||= agent_bot&.account_id
  end

  def url_is_http
    return if url.blank? || (url_valid?(url) && URI.parse(url).host.present?)

    errors.add(:url, I18n.t('errors.agent_bot_pages.url.invalid'))
  end

  def pages_limit
    return if agent_bot_id.nil? || self.class.where(agent_bot_id: agent_bot_id).count < MAX_PAGES_PER_BOT

    errors.add(:base, I18n.t('errors.agent_bot_pages.limit', count: MAX_PAGES_PER_BOT))
  end
end
