# What the AI agent knows about a conversation it replies to: the visitor, whether the team is available, and the recent
# public messages up to the message being answered.
class AiAgents::ConversationContext
  HISTORY_LIMIT = 30
  MESSAGE_LIMIT = 2_000
  # Widget contacts get a Haikunator name, such as bold-river-421, until the visitor gives their own
  GENERATED_NAME = /\A[a-z]+-[a-z]+-\d+\z/

  # team: the handoff team of the bot, or nil
  pattr_initialize [:conversation!, :message!, :team]

  # Never the email address itself, only whether it is known
  def visitor
    contact = conversation.contact
    {
      name: contact.name.to_s.match?(GENERATED_NAME) ? nil : contact.name.presence,
      company: contact.additional_attributes&.dig('company_name').presence,
      email_known: contact.email.present?,
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
