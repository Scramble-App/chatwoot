# Replies to a visitor message as an AI agent bot. One reply of a conversation runs at a time: a job that finds the
# conversation locked waits and retries, then replies only if its message is still the latest, so a burst of messages
# gets one reply, to the last one.
class AgentBots::AiAgentReplyJob < MutexApplicationJob
  queue_as :high

  LOCK_KEY = 'AI_AGENT_REPLY_LOCK::%<conversation_id>d'.freeze
  # Outlasts the longest reply: no OpenAI request starts after the responder's deadline, and one takes TIMEOUT_SECONDS at most
  LOCK_TIMEOUT = (AiAgents::Responder::DEADLINE_SECONDS + AiAgents::Responder::TIMEOUT_SECONDS + 60).seconds

  retry_on LockAcquisitionError, wait: 3.seconds, attempts: 100 do |job, _error|
    Rails.logger.warn("[ai-agent] gave up waiting for the reply lock of message #{job.arguments.second}")
  end

  def perform(agent_bot_id, message_id)
    agent_bot = AgentBot.find_by(id: agent_bot_id)
    message = Message.find_by(id: message_id)
    return if agent_bot.nil? || message.nil?

    with_lock(format(LOCK_KEY, conversation_id: message.conversation_id), LOCK_TIMEOUT) do
      next unless AiAgents::ReplyConditions.new(agent_bot: agent_bot, message: message).met?

      AiAgents::ReplyService.new(agent_bot: agent_bot, message: message).perform
    end
  end
end
