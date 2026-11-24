# Records a question the AI agent couldn't answer for the knowledge base team: finds the needs_answer entry of the bot
# whose question is the most similar (pg_trgm similarity above 0.5) or creates one, then adds the visitor's own wording
# with its conversation and counts the occurrence.
class AiAgents::UnansweredRecorder
  SIMILARITY_THRESHOLD = 0.5
  ATTEMPTS = 3

  # question: the unanswered question in English; message: the visitor message being answered
  pattr_initialize [:agent_bot!, :conversation!, :message!, :question!]

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

  # Of the visitor's messages up to the one being answered, the one most similar to the question (the latest on a tie),
  # so a later message that only gives an email isn't taken for the question
  def wording
    candidates = conversation.messages.incoming.where(private: false).where('messages.id <= ?', message.id).where.not(content: [nil, ''])
    order = AgentBotKnowledgeEntry.sanitize_sql_array(['similarity(messages.content, ?) DESC, messages.id DESC', entry_question])
    content = candidates.reorder(Arel.sql(order)).pick(:content).presence || entry_question
    content.truncate(AgentBotKnowledgeQuestion::CONTENT_LIMIT)
  end
end
