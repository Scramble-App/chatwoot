require 'rails_helper'

RSpec.describe AgentBotKnowledge::CsvExportService do
  let(:agent_bot) { create(:agent_bot, :ai_agent) }

  def exported_rows
    csv = described_class.new(agent_bot: agent_bot).perform
    expect(csv).to start_with("\uFEFF")
    CSV.parse(csv.delete_prefix("\uFEFF"))
  end

  it 'exports the sheet of the team with the entries of the bot by key' do
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-002', category: 'Pricing', frequency: 'Frequent',
                                       question: 'Are there fees?', alternative_questions: "Any fees?\nIs it free?", short_answer: 'No.',
                                       answer: 'There are no fees.', selling_point: 'Keep your revenue.')
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'Who can apply?', status: :needs_answer,
                                       short_answer: nil, answer: nil)
    create(:agent_bot_knowledge_entry, key: 'KB-003', question: 'Another bot?')

    expect(exported_rows).to eq(
      [
        ['ID', 'Категория', 'Частота', 'Вопрос', 'Другие формулировки клиентов', 'Короткий ответ', 'Развёрнутый ответ',
         'Аргумент для клиента', 'Статус'],
        ['KB-001', nil, nil, 'Who can apply?', nil, nil, nil, nil, 'needs_answer'],
        ['KB-002', 'Pricing', 'Frequent', 'Are there fees?', "Any fees?\nIs it free?", 'No.', 'There are no fees.', 'Keep your revenue.',
         'published']
      ]
    )
  end

  it 'quotes a cell that starts with a formula character' do
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: '=HYPERLINK("https://example.com")',
                                       answer: '- first point', short_answer: 'Plain answer.')

    expect(exported_rows.second.values_at(3, 5, 6)).to eq(["'=HYPERLINK(\"https://example.com\")", 'Plain answer.', "'- first point"])
  end
end
