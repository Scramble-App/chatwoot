# Replies to a visitor message as an AI agent bot. One reply of a conversation runs at a time: a job that finds the
# conversation locked waits and retries, then replies only if its message is still the latest, so a burst of messages
# gets one reply, to the last one.
class AgentBots::AiAgentReplyJob < MutexApplicationJob
  queue_as :high

  LOCK_KEY = 'AI_AGENT_REPLY_LOCK::%<conversation_id>d'.freeze
  # A reply can take several OpenAI calls of up to 45 seconds each (tool rounds and a corrective retry)
  LOCK_TIMEOUT = 5.minutes

  retry_on LockAcquisitionError, wait: 3.seconds, attempts: 100 do |job, _error|
    Rails.logger.warn("[ai-agent] gave up waiting for the reply lock of message #{job.arguments.second}")
  end

  def perform(agent_bot_id, message_id)
    agent_bot = AgentBot.find_by(id: agent_bot_id)
    message = Message.find_by(id: message_id)
    return if agent_bot.nil? || message.nil?

    with_lock(format(LOCK_KEY, conversation_id: message.conversation_id), LOCK_TIMEOUT) do
      AiAgents::ReplyService.new(agent_bot: agent_bot, message: message).perform if replyable?(agent_bot, message)
    end
  end

  private

  def replyable?(agent_bot, message)
    conversation = message.conversation
    agent_bot.ai_agent? && active_bot?(agent_bot, conversation) && conversation.pending? && conversation.assignee_id.nil? &&
      awaiting_reply?(agent_bot, message)
  end

  def active_bot?(agent_bot, conversation)
    return true if conversation.assignee_agent_bot_id == agent_bot.id

    agent_bot_inbox = conversation.inbox.agent_bot_inbox
    agent_bot_inbox.present? && agent_bot_inbox.active? && agent_bot_inbox.agent_bot_id == agent_bot.id
  end

  # The latest incoming public message, not answered by the bot yet (a retried job must not reply twice)
  def awaiting_reply?(agent_bot, message)
    public_messages = message.conversation.messages.where(private: false)
    public_messages.incoming.reorder(id: :desc).pick(:id) == message.id &&
      !public_messages.outgoing.where(sender: agent_bot).exists?(['messages.id > ?', message.id])
  end
end
