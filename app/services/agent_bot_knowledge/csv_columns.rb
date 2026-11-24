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

  # Ignores case, surrounding spaces and ё written as е
  def self.normalize(header)
    header.to_s.strip.downcase.tr('ё', 'е')
  end

  # Normalized sheet header or attribute name => attribute
  ATTRIBUTES_BY_NAME = HEADERS.flat_map { |attribute, header| [[normalize(header), attribute], [attribute.to_s, attribute]] }.to_h.freeze

  def self.attribute_for(header)
    ATTRIBUTES_BY_NAME[normalize(header)]
  end
end
