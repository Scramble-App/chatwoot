# Whether an AI agent bot may reply to a visitor message: the bot is an ai_agent and the active bot of the inbox or the bot
# of the conversation, the conversation is pending without an assignee, and the message is the latest incoming public
# message and has no reply of the bot yet. Everything is read fresh, so it is checked again after the model call: the
# visitor may have written again, or an agent may have taken over, while the model was working.
class AiAgents::ReplyConditions
  pattr_initialize [:agent_bot!, :message!]

  def met?
    agent_bot.reload
    conversation = message.conversation.reload
    agent_bot.ai_agent? && active_bot?(conversation) && conversation.pending? && conversation.assignee_id.nil? &&
      latest_incoming?(conversation) && !answered?(conversation)
  end

  private

  def active_bot?(conversation)
    return true if conversation.assignee_agent_bot_id == agent_bot.id

    agent_bot_inbox = conversation.inbox.agent_bot_inbox
    agent_bot_inbox.present? && agent_bot_inbox.active? && agent_bot_inbox.agent_bot_id == agent_bot.id
  end

  def latest_incoming?(conversation)
    conversation.messages.incoming.where(private: false).reorder(id: :desc).pick(:id) == message.id
  end

  # The reply and the fallback message name the message they answer, so a retried job doesn't answer it twice
  def answered?(conversation)
    conversation.messages.outgoing.where(sender: agent_bot).where('messages.id > ?', message.id)
                .any? { |reply| reply.content_attributes['ai_agent_reply_to'] == message.id }
  end
end
