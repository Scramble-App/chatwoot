require 'rails_helper'

RSpec.describe AgentBotKnowledge::CsvImportService do
  let(:agent_bot) { create(:agent_bot, :ai_agent) }
  let(:sheet_headers) do
    ['ID', 'Категория', 'Частота', 'Вопрос', 'Другие формулировки клиентов', 'Короткий ответ', 'Развёрнутый ответ', 'Аргумент для клиента']
  end

  def csv_file(content)
    Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: 'knowledge.csv')
  end

  def import(content, dry_run: false)
    described_class.new(agent_bot: agent_bot, file: csv_file(content), dry_run: dry_run).perform
  end

  def entries
    agent_bot.knowledge_entries.order(:key)
  end

  describe 'columns' do
    it 'reads the sheet of the team with a BOM' do
      csv = CSV.generate do |rows|
        rows << sheet_headers
        rows << ['KB-001', 'Pricing', 'Frequent', 'Are there fees?', "Any fees?\nIs it free?", 'No fees.', 'There are no fees at all.',
                 'Keep all your revenue.']
      end

      expect(import("\uFEFF#{csv}")).to eq(created: 1, updated: 0, errors: [])
      expect(entries.first).to have_attributes(
        key: 'KB-001', category: 'Pricing', frequency: 'Frequent', question: 'Are there fees?', alternative_questions: "Any fees?\nIs it free?",
        short_answer: 'No fees.', answer: 'There are no fees at all.', selling_point: 'Keep all your revenue.', status: 'published',
        account_id: agent_bot.account_id
      )
    end

    it 'matches the headers by sheet or attribute name, ignoring case, spaces and ё' do
      csv = " id ,QUESTION, развернутый ОТВЕТ ,Short_Answer,Notes\nKB-001,Are there fees?,No fees at all.,No.,ignored\n"

      import(csv)

      expect(entries.first).to have_attributes(key: 'KB-001', question: 'Are there fees?', answer: 'No fees at all.', short_answer: 'No.')
    end

    it 'reads a sheet that Excel saved with semicolons' do
      csv = "ID;Вопрос;Короткий ответ;Статус\r\nKB-001;\"Fees, terms; and more?\";No, none.;draft\r\n"

      expect(import(csv)).to eq(created: 1, updated: 0, errors: [])
      expect(entries.first).to have_attributes(key: 'KB-001', question: 'Fees, terms; and more?', short_answer: 'No, none.', status: 'draft')
    end

    it 'keeps commas when they split the headers into more known columns' do
      import("ID,Вопрос,\"Notes; misc\"\nKB-007,\"Fees; terms?\",ignored\n")

      expect(entries.pluck(:key, :question)).to eq([['KB-007', 'Fees; terms?']])
    end

    it 'rejects a file without any column of the sheet' do
      expect { import("Name,Email\nJane,jane@example.com\n") }
        .to raise_error(described_class::Error, /none of the knowledge base columns: ID, Категория/)
    end

    it 'skips blank rows and counts the rows of the sheet' do
      result = import("Вопрос,Статус\n,\n\nNew?,archived\n")

      expect(result[:errors]).to eq([{ row: 4, message: 'Status is not included in the list' }])
    end
  end

  describe 'upsert' do
    let!(:entry) do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', category: 'Pricing', question: 'Old question?',
                                         short_answer: 'Old answer.', answer: nil, status: :draft)
    end

    it 'updates the entry of a key, only in the columns of the file, and keeps its status' do
      result = import("ID,Вопрос,Развёрнутый ответ\nKB-001,New question?,New detailed answer.\n")

      expect(result).to eq(created: 0, updated: 1, errors: [])
      expect(entry.reload).to have_attributes(question: 'New question?', answer: 'New detailed answer.', category: 'Pricing',
                                              short_answer: 'Old answer.', status: 'draft')
    end

    it 'clears a field with a blank cell' do
      import("ID,Категория\nKB-001,\n")

      expect(entry.reload.category).to be_nil
    end

    it 'does not count an entry without changes as updated' do
      expect(import("ID,Вопрос,Категория\nKB-001,Old question?,Pricing\n")).to eq(created: 0, updated: 0, errors: [])
    end

    it 'sets the status of the status column' do
      import("ID,Статус\nKB-001,Published\n")

      expect(entry.reload.status).to eq('published')
    end

    it 'creates the entry of a new key' do
      import("ID,Вопрос\nPRICING-1,New question?\n")

      expect(entries.pluck(:key)).to eq(%w[KB-001 PRICING-1])
    end
  end

  describe 'new entries' do
    it 'publishes an entry with an answer and marks one without as needing an answer' do
      import("Вопрос,Короткий ответ,Развёрнутый ответ\nWith short?,Yes.,\nWith detailed?,,Yes.\nWithout?,,\n")

      expect(entries.pluck(:question, :status)).to eq(
        [['With short?', 'published'], ['With detailed?', 'published'], ['Without?', 'needs_answer']]
      )
    end

    it 'takes the status of a filled status cell' do
      import("Вопрос,Короткий ответ,Статус\nWith short?,Yes.,draft\nWithout?,,\n")

      expect(entries.pluck(:status)).to eq(%w[draft needs_answer])
    end

    it 'numbers blank keys after the highest KB- number of the bot and of the file' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-004')

      result = import("ID,Вопрос\n,First?\nKB-010,Tenth?\n,Second?\n")

      expect(result).to eq(created: 3, updated: 0, errors: [])
      expect(entries.pluck(:key, :question)).to eq(
        [['KB-004', entries.first.question], ['KB-010', 'Tenth?'], ['KB-011', 'First?'], ['KB-012', 'Second?']]
      )
    end
  end

  describe 'dry run' do
    it 'returns the counts without saving' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'Old question?')

      result = import("ID,Вопрос\nKB-001,New question?\n,Another?\n,Third?\n", dry_run: true)

      expect(result).to eq(created: 2, updated: 1, errors: [])
      expect(entries.pluck(:key, :question)).to eq([['KB-001', 'Old question?']])
    end

    it 'does not take the key lock' do
      allow(AgentBotKnowledgeEntry).to receive(:lock_keys!).and_call_original

      import("Вопрос\nNew?\n", dry_run: true)

      expect(AgentBotKnowledgeEntry).not_to have_received(:lock_keys!)
    end
  end

  describe 'key lock' do
    it 'locks the keys of the bot before it numbers the new entries' do
      allow(AgentBotKnowledgeEntry).to receive(:lock_keys!).and_call_original
      allow(AgentBotKnowledgeEntry).to receive(:next_key_number).and_call_original

      import("Вопрос\nFirst?\nSecond?\n")

      expect(AgentBotKnowledgeEntry).to have_received(:lock_keys!).with(agent_bot.id).once.ordered
      expect(AgentBotKnowledgeEntry).to have_received(:next_key_number).with(agent_bot.id).once.ordered
      expect(entries.pluck(:key)).to eq(%w[KB-001 KB-002])
    end

    it 'checks the uniqueness of each new key once' do
      key_checks = []
      count_key_checks = lambda do |*, payload|
        key_checks << payload[:sql] if payload[:sql].start_with?('SELECT 1 AS one FROM "agent_bot_knowledge_entries"')
      end

      ActiveSupport::Notifications.subscribed(count_key_checks, 'sql.active_record') { import("Вопрос\nFirst?\nSecond?\nThird?\n") }

      expect(key_checks.size).to eq(3)
      expect(entries.count).to eq(3)
    end

    it 'asks to import again when an entry with a key of the file was saved meanwhile' do
      saves = 0
      # The race needs an entry saved between the validation and the save of the import, so the second save fails
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(AgentBotKnowledgeEntry).to receive(:save!).and_wrap_original do |original, *args, **options|
        saves += 1
        raise ActiveRecord::RecordNotUnique if saves == 2

        original.call(*args, **options)
      end
      # rubocop:enable RSpec/AnyInstance

      expect { import("ID,Вопрос\nPRICING-1,First?\nPRICING-2,Second?\n") }
        .to raise_error(described_class::Error, 'The knowledge base changed during the import, so nothing was imported. Import the file again.')
      expect(entries).to be_empty
    end
  end

  describe 'invalid rows' do
    it 'saves nothing and returns every row error with its sheet row' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'Old question?')
      csv = "ID,Вопрос,Короткий ответ,Статус\nKB-001,New question?,,\n,,,\nKB-002,,,\nKB-003,Published?,,published\n" \
            "KB-001,Again?,,\nKB-004,#{'a' * 2_001},,\nKB 6,Spaced key?,,\nKB-005,Fine?,,\nKB-007,Archived?,,archived\n"

      result = import(csv)

      expect(result[:errors]).to eq(
        [
          { row: 4, message: "Question can't be blank" },
          { row: 5, message: 'Answer or short answer is required to publish the entry' },
          { row: 6, message: 'The key KB-001 is already in row 2' },
          { row: 7, message: 'Question is too long (maximum is 2000 characters)' },
          { row: 8, message: 'Key is invalid' },
          { row: 10, message: 'Status is not included in the list' }
        ]
      )
      expect(result.slice(:created, :updated)).to eq(created: 1, updated: 1)
      expect(entries.pluck(:key, :question)).to eq([['KB-001', 'Old question?']])
    end
  end

  describe 'export round trip' do
    it 'reads the formula characters the export quotes' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: '=1+1?',
                                                 answer: "- one\n- two", short_answer: '+ more', selling_point: '@scramble')
      csv = AgentBotKnowledge::CsvExportService.new(agent_bot: agent_bot).perform
      entry.update!(question: 'Changed?', answer: 'Changed.', short_answer: nil, selling_point: nil)

      expect(import(csv)).to eq(created: 0, updated: 1, errors: [])
      expect(entry.reload).to have_attributes(question: '=1+1?', answer: "- one\n- two", short_answer: '+ more', selling_point: '@scramble')
    end

    it 'finds no changes in an unchanged export' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', category: 'Pricing', frequency: 'Rare',
                                         alternative_questions: "One?\nTwo?", selling_point: 'Point.')
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer, answer: nil, short_answer: nil)

      expect(import(AgentBotKnowledge::CsvExportService.new(agent_bot: agent_bot).perform)).to eq(created: 0, updated: 0, errors: [])
    end

    it 'finds no changes in an export of entries saved with surrounding spaces' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, category: ' Pricing ', question: "Are there fees?\n",
                                         answer: "No fees.\n\n", selling_point: ' ', frequency: '')

      expect(import(AgentBotKnowledge::CsvExportService.new(agent_bot: agent_bot).perform)).to eq(created: 0, updated: 0, errors: [])
    end
  end

  describe 'file errors' do
    it 'rejects a missing file' do
      expect { described_class.new(agent_bot: agent_bot, file: nil).perform }
        .to raise_error(described_class::Error, 'Choose a CSV file to import')
    end

    it 'rejects a file over 5 MB' do
      file = csv_file("Вопрос\n#{'a' * 5.megabytes}\n")

      expect { described_class.new(agent_bot: agent_bot, file: file).perform }
        .to raise_error(described_class::Error, 'The file is larger than 5 MB')
    end

    it 'rejects more than 5,000 rows before it reads the rest of the file' do
      expect { import("Вопрос\n#{"Question?\n" * 5_001}\"Unclosed\n") }.to raise_error(described_class::Error, 'The file has more than 5000 rows')
    end

    it 'limits the rows with an entry and stops a file of blank rows early' do
      stub_const("#{described_class}::MAX_ROWS", 3)
      stub_const("#{described_class}::MAX_LINES", 5)

      expect(import("Вопрос\nFirst?\nSecond?\nThird?\n\n", dry_run: true)).to include(created: 3)
      expect { import("Вопрос\nFirst?\n\nSecond?\nThird?\nFourth?\n", dry_run: true) }
        .to raise_error(described_class::Error, 'The file has more than 3 rows')
      expect { import("Вопрос\n#{"\n" * 6}", dry_run: true) }.to raise_error(described_class::Error, 'The file has more than 5 rows')
    end

    it 'rejects a very wide header before it reads the column names' do
      allow(AgentBotKnowledge::CsvColumns).to receive(:attribute_for).and_call_original
      message = 'The header row of the file is too long: keep it under 8 KB and 100 columns'

      expect { import("Вопрос#{',a' * 2_500_000}\nNew?\n") }.to raise_error(described_class::Error, message)
      expect(AgentBotKnowledge::CsvColumns).not_to have_received(:attribute_for)

      expect { import("Вопрос#{',a' * 100}\nNew?\n") }.to raise_error(described_class::Error, message)
      expect(AgentBotKnowledge::CsvColumns).to have_received(:attribute_for).once
    end

    it 'rejects a file that is not UTF-8' do
      expect { import("Вопрос\nВопрос?\n".encode('windows-1251')) }
        .to raise_error(described_class::Error, 'The file must be a CSV file in UTF-8')
    end

    it 'rejects a malformed CSV file' do
      expect { import("Вопрос\n\"Unclosed?\n") }.to raise_error(described_class::Error, /The file is not a valid CSV file: Unclosed quoted field/)
    end
  end
end
