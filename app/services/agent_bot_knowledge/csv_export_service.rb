# Exports the knowledge base of an AI agent bot as a CSV file of the team's sheet (AgentBotKnowledge::CsvColumns), in UTF-8
# with a BOM so Excel reads it. CSVSafe quotes a cell that starts with a formula character; the import removes that quote.
class AgentBotKnowledge::CsvExportService
  pattr_initialize [:agent_bot!]

  def perform
    csv = CSVSafe.generate do |rows|
      rows << AgentBotKnowledge::CsvColumns::HEADERS.values
      agent_bot.knowledge_entries.order(:key).each do |entry|
        rows << AgentBotKnowledge::CsvColumns::HEADERS.keys.map { |attribute| entry.public_send(attribute) }
      end
    end
    "\uFEFF#{csv}"
  end
end
