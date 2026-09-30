module AiGeneratable
  extend ActiveSupport::Concern

  # Each Onyx and OpenAI request may take up to 2 minutes, so a slow but healthy job can run past 5 minutes
  STALE_TIMEOUT = 10.minutes
  CONTENT_LIMIT = 150_000
  ERROR_MESSAGE_LIMIT = 10_000

  included do
    enum status: { pending: 0, running: 1, completed: 2, failed: 3 }

    belongs_to :account
    belongs_to :conversation
    belongs_to :user

    validates :provider, presence: true
    validates :content, length: { maximum: CONTENT_LIMIT }, allow_blank: true
    validates :error_message, length: { maximum: ERROR_MESSAGE_LIMIT }, allow_blank: true
    validates :conversation_id, uniqueness: { scope: :user_id }
  end

  def in_progress?
    pending? || running?
  end

  def stale?
    in_progress? && updated_at < STALE_TIMEOUT.ago
  end

  def mark_running!
    update!(status: :running)
  end

  # Content over the limit would fail validation and then make fail! raise too, so Sidekiq would rerun the paid generation
  def complete!(generated_content)
    update!(status: :completed, content: generated_content.truncate(CONTENT_LIMIT), error_message: nil)
  end

  def fail!(message)
    update!(status: :failed, error_message: message.to_s.truncate(ERROR_MESSAGE_LIMIT))
  end

  def reset_for_retry!(attributes = {})
    update!({ status: :pending, content: nil, error_message: nil }.merge(attributes))
  end

  def push_event_data
    {
      id: id,
      status: stale? ? 'failed' : status,
      content: content,
      error_message: stale? ? I18n.t('ai_generations.stale') : error_message,
      provider: provider,
      updated_at: updated_at.to_i
    }
  end
end
