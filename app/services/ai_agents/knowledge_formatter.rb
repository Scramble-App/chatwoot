# The KNOWLEDGE BASE section of the AI agent prompt: one block per entry, sorted by category, then key number, then key.
#
#   #KB-021 Pricing | How is my monthly repayment calculated?
#   Short: ...
#   Full: ...
#   Point: ...
#
# A blank field drops its line, a blank category drops its part of the first line, and entries are separated by one
# blank line. Blank lines inside a field are removed so they can't be mistaken for the end of an entry.
class AiAgents::KnowledgeFormatter
  FIELDS = { 'Short' => :short_answer, 'Full' => :answer, 'Point' => :selling_point }.freeze

  def initialize(entries)
    @entries = entries
  end

  def to_s
    sorted_entries.map { |entry| format_entry(entry) }.join("\n\n")
  end

  private

  def sorted_entries
    @entries.sort_by { |entry| [entry.category.to_s.squish, key_number(entry.key), entry.key] }
  end

  # KB-9 comes before KB-10; other keys follow the numbered ones
  def key_number(key)
    key.to_s[/\AKB-(\d+)\z/, 1]&.to_i || Float::INFINITY
  end

  def format_entry(entry)
    category = entry.category.to_s.squish.presence
    lines = ["##{entry.key}#{" #{category}" if category} | #{entry.question.to_s.squish}"]
    FIELDS.each do |label, field|
      value = text(entry.public_send(field))
      lines << "#{label}: #{value}" if value
    end
    lines.join("\n")
  end

  def text(value)
    value.to_s.gsub(/\r\n?/, "\n").gsub(/\n[[:space:]]*\n/, "\n").strip.presence
  end
end
