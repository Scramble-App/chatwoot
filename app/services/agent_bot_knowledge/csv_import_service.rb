# Imports the knowledge base of an AI agent bot from a CSV file of the team's sheet (AgentBotKnowledge::CsvColumns).
# Rows are upserted by key and a blank key creates an entry with the next KB- number. Only the columns in the file are
# changed. A new entry without a status is published when it has an answer and needs an answer otherwise; an existing
# entry keeps its status. Nothing is saved on a dry run or when any row is invalid.
class AgentBotKnowledge::CsvImportService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  MAX_ROWS = 5_000
  COLUMN_SEPARATORS = [',', ';'].freeze
  KB_KEY = /\AKB-(\d+)\z/
  # The export quotes a cell that starts with a formula character (CSVSafe), so the import removes that quote again
  EXPORT_QUOTE = /\A'(?=[-=+@%|\r\t])/

  pattr_initialize [:agent_bot!, :file, :dry_run]

  # => { created:, updated:, errors: [{ row:, message: }] }, with the row numbers of the sheet (the header is row 1)
  def perform
    rows = parse_rows
    return build_result(rows) if dry_run

    # The lock keeps other entries of the bot from taking the new keys until the import is saved
    ActiveRecord::Base.transaction do
      AgentBotKnowledgeEntry.lock_keys!(agent_bot.id)
      build_result(rows).tap { |result| save if result[:errors].empty? }
    end
  end

  private

  def build_result(rows)
    prepare_keys(rows)
    @entries, errors = build_entries(rows)
    { created: @entries.count(&:new_record?), updated: @entries.count { |entry| entry.persisted? && entry.changed? }, errors: errors }
  end

  def parse_rows
    content = read_content
    header, *lines = CSV.parse(content, col_sep: column_separator(content))
    columns = columns_for(header)
    rows = lines.each_with_index.filter_map do |cells, index|
      [index + 2, columns.transform_values { |position| clean(cells[position]) }] unless cells.all?(&:blank?)
    end
    raise Error, I18n.t('agent_bot_knowledge.import.too_many_rows', count: MAX_ROWS) if rows.size > MAX_ROWS

    rows
  rescue CSV::MalformedCSVError => e
    raise Error, I18n.t('agent_bot_knowledge.import.invalid_csv', error: e.message)
  end

  # The UTF-8 text of the file without a BOM
  def read_content
    raise Error, I18n.t('agent_bot_knowledge.import.file_missing') unless file.respond_to?(:read)
    raise Error, I18n.t('agent_bot_knowledge.import.file_too_large', size: MAX_FILE_SIZE / 1.megabyte) if file.size > MAX_FILE_SIZE

    content = file.read.force_encoding(Encoding::UTF_8)
    raise Error, I18n.t('agent_bot_knowledge.import.invalid_encoding') unless content.valid_encoding?

    content.delete_prefix("\uFEFF")
  end

  # Excel with a Russian locale saves semicolons; the separator that finds more known headers wins, a comma on a tie
  def column_separator(content)
    header_line = content.each_line.first.to_s
    COLUMN_SEPARATORS.max_by do |separator|
      CSV.parse_line(header_line, col_sep: separator).to_a.count { |name| AgentBotKnowledge::CsvColumns.attribute_for(name) }
    rescue CSV::MalformedCSVError
      0
    end
  end

  # Attribute => position of its first column; other columns are ignored
  def columns_for(header)
    columns = {}
    Array(header).each_with_index do |name, position|
      attribute = AgentBotKnowledge::CsvColumns.attribute_for(name)
      columns[attribute] ||= position if attribute
    end
    raise Error, I18n.t('agent_bot_knowledge.import.no_columns', headers: AgentBotKnowledge::CsvColumns::HEADERS.values.join(', ')) if columns.empty?

    columns
  end

  def clean(value)
    value.to_s.sub(EXPORT_QUOTE, '').strip.presence
  end

  # Blank keys get numbers after the highest KB- number of the bot and of the file, so they never take a key of the file
  def prepare_keys(rows)
    keys = rows.filter_map { |_, attributes| attributes[:key] }
    @existing_entries = agent_bot.knowledge_entries.where(key: keys).index_by(&:key)
    @rows_by_key = {}
    file_numbers = keys.filter_map { |key| key[KB_KEY, 1]&.to_i }
    @last_key_number = [AgentBotKnowledgeEntry.next_key_number(agent_bot.id) - 1, *file_numbers].max
  end

  def build_entries(rows)
    entries = []
    errors = []
    rows.each do |row_number, attributes|
      entry, messages = build_entry(row_number, attributes)
      messages.empty? ? entries << entry : errors << { row: row_number, message: messages.join(', ') }
    end
    [entries, errors]
  end

  # => [entry, error messages]
  def build_entry(row_number, attributes)
    key = attributes[:key]
    return [nil, [I18n.t('agent_bot_knowledge.import.duplicate_key', key: key, row: @rows_by_key[key])]] if @rows_by_key.key?(key)

    @rows_by_key[key] = row_number if key
    entry = @existing_entries[key] || agent_bot.knowledge_entries.new(key: key || next_key)
    entry.assign_attributes(attributes.except(:key, :status))
    assign_status(entry, attributes[:status]&.downcase)
    [entry, entry.valid? ? [] : entry.errors.full_messages]
  end

  def next_key
    format(AgentBotKnowledgeEntry::KEY_FORMAT, @last_key_number += 1)
  end

  # An unknown status is a validation error of the entry
  def assign_status(entry, status)
    if status
      entry.status = status
    elsif entry.new_record?
      entry.status = [entry.answer, entry.short_answer].any?(&:present?) ? :published : :needs_answer
    end
  end

  def save
    @entries.each { |entry| entry.save! if entry.changed? }
  end
end
