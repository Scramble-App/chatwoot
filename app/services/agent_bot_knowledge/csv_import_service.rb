# Imports the knowledge base of an AI agent bot from a CSV file of the team's sheet (AgentBotKnowledge::CsvColumns).
# Rows are upserted by key and a blank key creates an entry with the next KB- number. Only the columns in the file are
# changed. A new entry without a status is published when it has an answer and needs an answer otherwise; an existing
# entry keeps its status. Nothing is saved on a dry run or when any row is invalid.
class AgentBotKnowledge::CsvImportService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  MAX_ROWS = 5_000
  # Blank rows are skipped, but they count here, so a file of them stops early too
  MAX_LINES = 2 * MAX_ROWS
  MAX_HEADER_SIZE = 8.kilobytes
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
  rescue ActiveRecord::RecordNotUnique => e
    # An entry with a key of the file was saved meanwhile; the transaction rolled the import back
    Rails.logger.warn("AgentBotKnowledge::CsvImportService rolled back for bot #{agent_bot.id}: #{e.message}")
    raise Error, I18n.t('agent_bot_knowledge.import.changed_meanwhile')
  end

  private

  def build_result(rows)
    prepare_keys(rows)
    @entries, errors = build_entries(rows)
    { created: @entries.count(&:new_record?), updated: @entries.count { |entry| entry.persisted? && entry.changed? }, errors: errors }
  end

  # The header is the text up to the first CR or LF, as CR-only files end their lines with CR. It must be a complete
  # row, so reading it is bounded by MAX_HEADER_SIZE, and csv.shift then skips exactly that row.
  # index finds the line end without the backtracking memory an anchored regex takes on a long line.
  def parse_rows
    content = read_content
    header_line = content[0, content.index(/[\r\n]/) || content.length]
    separator = column_separator(header_line)
    columns = columns_for(CSV.parse_line(header_line, col_sep: separator))
    csv = CSV.new(content, col_sep: separator)
    csv.shift
    data_rows(csv, columns)
  rescue CSV::MalformedCSVError => e
    raise Error, I18n.t('agent_bot_knowledge.import.invalid_csv', error: e.message)
  end

  # Reads row by row and stops past the limits, so a large file is never loaded whole
  def data_rows(csv, columns)
    rows = []
    csv.each.with_index(2) do |cells, row_number|
      raise too_many_rows(MAX_LINES) if row_number > MAX_LINES + 1
      next if cells.all?(&:blank?)

      rows << [row_number, columns.transform_values { |position| clean(cells[position]) }]
      raise too_many_rows(MAX_ROWS) if rows.size > MAX_ROWS
    end
    rows
  end

  def too_many_rows(count)
    Error.new(I18n.t('agent_bot_knowledge.import.too_many_rows', count: count))
  end

  def header_too_long
    Error.new(I18n.t('agent_bot_knowledge.import.header_too_long', size: MAX_HEADER_SIZE / 1.kilobyte))
  end

  # The UTF-8 text of the file without a BOM
  def read_content
    raise Error, I18n.t('agent_bot_knowledge.import.file_missing') unless file.respond_to?(:read)
    raise Error, I18n.t('agent_bot_knowledge.import.file_too_large', size: MAX_FILE_SIZE / 1.megabyte) if file.size > MAX_FILE_SIZE

    content = file.read.force_encoding(Encoding::UTF_8)
    raise Error, I18n.t('agent_bot_knowledge.import.invalid_encoding') unless content.valid_encoding?
    # A CSV text file has no NULs, and PostgreSQL would reject them on save
    raise Error, I18n.t('agent_bot_knowledge.import.null_character') if content.include?("\u0000")

    content.delete_prefix("\uFEFF")
  end

  # Excel with a Russian locale saves semicolons; the separator that finds more known headers wins, a comma on a tie.
  # The size limit keeps the header to a few thousand cells, each one hash lookup.
  def column_separator(header_line)
    raise header_too_long if header_line.bytesize > MAX_HEADER_SIZE

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
    # Keys are compared the way the model stores them, so a key pasted with a non-breaking space still matches its entry
    rows.map(&:last).each { |attributes| attributes[:key] = normalized_key(attributes[:key]) if attributes.key?(:key) }
    keys = rows.filter_map { |_, attributes| attributes[:key] }
    @existing_entries = agent_bot.knowledge_entries.where(key: keys).index_by(&:key)
    @rows_by_key = {}
    file_numbers = keys.filter_map { |key| key[KB_KEY, 1]&.to_i }
    @last_key_number = [AgentBotKnowledgeEntry.next_key_number(agent_bot.id) - 1, *file_numbers].max
  end

  def normalized_key(key)
    AgentBotKnowledgeEntry.normalize_value_for(:key, key).presence if key
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

  # The entries were validated moments ago in this transaction, under the key lock
  def save
    @entries.each { |entry| entry.save!(validate: false) if entry.changed? }
  end
end
