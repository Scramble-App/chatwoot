class Conversations::ReopenSnoozedConversationsJob < ApplicationJob
  queue_as :low

  def perform
    Conversation.where(status: :snoozed).where(snoozed_until: 3.days.ago..Time.current).all.find_each(batch_size: 100) do |conversation|
      reopen_for_follow_up(conversation)
    end
  end

  private

  # The snooze time is when the agent promised to follow up, so the conversation now waits for an agent reply,
  # like after a customer message. Without that, auto-resolve saw the old reply as the last activity and closed it right away.
  def reopen_for_follow_up(conversation)
    conversation.update!(status: :open, waiting_since: conversation.waiting_since || Time.current, last_activity_at: Time.current)
  end
end
