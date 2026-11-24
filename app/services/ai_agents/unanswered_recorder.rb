# Records a question the AI agent couldn't answer for the knowledge base team: finds the needs_answer entry of the bot
# whose English question is the most similar (pg_trgm similarity above 0.5) or creates one, then adds the visitor's own
# wording with its conversation and counts the occurrence.
class AiAgents::UnansweredRecorder
  SIMILARITY_THRESHOLD = 0.5
  ATTEMPTS = 3
  # The visitor messages searched for the wording, at most as many as the prompt history holds
  RECENT_MESSAGES = AiAgents::ConversationContext::HISTORY_LIMIT
  EMAIL = /\S+@\S+/
  # Shorter messages without a question mark are acknowledgements, such as "Yes, please"
  QUESTION_MIN_WORDS = 4

  # question: the unanswered question in English; visitor_question: the visitor's own words for it, as the model copied
  # them; message: the visitor message being answered
  pattr_initialize [:agent_bot!, :conversation!, :message!, :question!, { visitor_question: nil }]

  def perform
    attempts = 0
    begin
      attempts += 1
      # A savepoint, so a failed insert can be retried inside an outer transaction too
      AgentBotKnowledgeEntry.transaction(requires_new: true) { record }
    # New keys are numbered under an advisory lock of the bot; a key that is still taken (e.g. by an import) gets a retry
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < ATTEMPTS
      raise
    end
  end

  private

  def record
    entry = similar_entry || agent_bot.knowledge_entries.create!(question: entry_question, status: :needs_answer)
    entry.questions.create!(conversation: conversation, content: wording)
    # One atomic UPDATE, so concurrent conversations don't lose a count
    AgentBotKnowledgeEntry.update_counters(entry.id, asked_count: 1, touch: :last_asked_at) # rubocop:disable Rails/SkipsModelValidations
    entry
  end

  def entry_question
    question.truncate(AgentBotKnowledgeEntry::QUESTION_LIMIT)
  end

  def similar_entry
    agent_bot.knowledge_entries.needs_answer
             .where('similarity(question, ?) > ?', entry_question, SIMILARITY_THRESHOLD)
             .reorder(Arel.sql(AgentBotKnowledgeEntry.sanitize_sql_array(['similarity(question, ?) DESC', entry_question])))
             .first
  end

  # The visitor's words as the model copied them, if one of their recent messages has them, so a translation or a made-up
  # wording is never stored. Otherwise their latest message that asks something, so not just an email or "yes, please",
  # then their latest message.
  def wording
    contents = recent_contents
    text = copied_wording(contents) || contents.find { |content| asks_something?(content) } || contents.first || entry_question
    text.squish.truncate(AgentBotKnowledgeQuestion::CONTENT_LIMIT)
  end

  # Newest first, up to the message being answered
  def recent_contents
    conversation.messages.incoming.where(private: false).where('messages.id <= ?', message.id).where.not(content: [nil, ''])
                .reorder(id: :desc).limit(RECENT_MESSAGES).pluck(:content)
  end

  # Ignoring case and spacing, a message contains the copy, or the copy contains a whole message that asks something
  def copied_wording(contents)
    copy = visitor_question.to_s.squish
    return if copy.empty?

    copy if contents.any? do |content|
      text = content.squish.downcase
      text.include?(copy.downcase) || (asks_something?(content) && copy.downcase.include?(text))
    end
  end

  def asks_something?(content)
    text = content.gsub(EMAIL, ' ').squish
    text.include?('?') || text.split.size >= QUESTION_MIN_WORDS
  end
end
