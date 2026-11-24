# The columns of the team's knowledge base sheet, shared by the CSV import and export
module AgentBotKnowledge::CsvColumns
  # Attribute => header of the sheet, in the sheet's order
  HEADERS = {
    key: 'ID',
    category: 'Категория',
    frequency: 'Частота',
    question: 'Вопрос',
    alternative_questions: 'Другие формулировки клиентов',
    short_answer: 'Короткий ответ',
    answer: 'Развёрнутый ответ',
    selling_point: 'Аргумент для клиента',
    status: 'Статус'
  }.freeze

  # Matches the sheet header or the attribute name, ignoring case, surrounding spaces and ё written as е
  def self.attribute_for(header)
    name = normalize(header)
    HEADERS.find { |attribute, sheet_header| [attribute.to_s, normalize(sheet_header)].include?(name) }&.first
  end

  def self.normalize(header)
    header.to_s.strip.downcase.tr('ё', 'е')
  end
end
