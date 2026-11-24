# What the AI agent knows about a conversation it replies to: the visitor, whether the team is available, and the recent
# public messages up to the message being answered.
class AiAgents::ConversationContext
  HISTORY_LIMIT = 30
  MESSAGE_LIMIT = 2_000
  # Conversation additional attribute with the name and company the visitor gave the agent (save_contact)
  VISITOR_DETAILS = 'ai_agent_visitor'.freeze

  # team: the handoff team of the bot, or nil
  pattr_initialize [:conversation!, :message!, :team]

  # The name and company only as the visitor gave them in this conversation: an email can merge the visitor into another
  # customer's contact. Whether an email is known reveals nothing; the address itself is never given.
  def visitor
    given = conversation.additional_attributes&.dig(VISITOR_DETAILS) || {}
    {
      name: given['name'].presence,
      company: given['company'].presence,
      email_known: conversation.contact.email.present?,
      browser_language: conversation.additional_attributes&.dig('browser_language').presence
    }
  end

  # Whether an online inbox member, of the handoff team when there is one, can take the conversation. This is the
  # availability auto assignment uses: OnlineStatusTracker, where agents with a schedule are online during their shifts.
  def team_available?
    agents = conversation.inbox.available_agents
    agents = agents.where(user_id: team.team_members.select(:user_id)) if team
    agents.exists?
  end

  # The visitor is the user; the bot, inbox templates and team members (marked) are the assistant
  def history
    messages = conversation.messages.chat.where('messages.id <= ?', message.id).reorder(id: :desc).limit(HISTORY_LIMIT)
    messages.includes(:attachments).reverse.filter_map do |history_message|
      text = history_text(history_message)
      next if text.blank?
      next { role: 'user', content: text } if history_message.incoming?

      { role: 'assistant', content: history_message.sender_type == 'User' ? "[Team member] #{text}" : text }
    end
  end

  private

  def history_text(history_message)
    attachments = history_message.attachments.map { |attachment| "[attachment: #{attachment.file_type}]" }
    [history_message.content.to_s.strip.truncate(MESSAGE_LIMIT).presence, *attachments].compact.join("\n")
  end
end
