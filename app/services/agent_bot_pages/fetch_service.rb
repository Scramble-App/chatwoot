# Fetches a website page of an AI agent bot through SafeFetch, which blocks private networks, and keeps its title and
# main text. A failed fetch marks the page failed and keeps its previous content.
class AgentBotPages::FetchService
  class Error < StandardError; end

  MAX_BYTES = 5.megabytes
  CONTENT_TYPES = %w[text/html application/xhtml+xml].freeze
  NOISE_SELECTOR = 'script, style, noscript, svg, nav, header, footer, form, iframe, template'.freeze
  TITLE_LIMIT = 255
  ERROR_LIMIT = 1_000

  pattr_initialize [:page!]

  # Any error of the request or the parsing fails the page; an error saving it is raised
  def perform
    document = Nokogiri::HTML(download)
    title = title_of(document)
    content = main_text(document)
    raise Error, I18n.t('agent_bot_knowledge.pages.no_text') if content.blank?
  rescue StandardError => e
    Rails.logger.info("AgentBotPages::FetchService failed for page #{page.id}: #{e.class} #{e.message}")
    page.update!(status: :failed, error_message: e.message.truncate(ERROR_LIMIT))
  else
    page.update!(title: title, content: content, status: :fetched, fetched_at: Time.current, error_message: nil)
  end

  private

  def download
    SafeFetch.fetch(page.url, max_bytes: MAX_BYTES, allowed_content_type_prefixes: [], allowed_content_types: CONTENT_TYPES) do |result|
      html = result.tempfile.read.force_encoding(Encoding::UTF_8)
      # Other bytes than UTF-8 are left to Nokogiri, which reads the charset the page declares
      html.valid_encoding? ? html : html.force_encoding(Encoding::BINARY)
    end
  end

  def title_of(document)
    title = document.at_css('meta[property="og:title"]')&.[]('content').presence || document.title
    title.to_s.squish.truncate(TITLE_LIMIT).presence
  end

  # Markdown keeps the headings, lists, tables and links; ReverseMarkdown writes a non-breaking space as &nbsp;
  def main_text(document)
    document.css(NOISE_SELECTOR).remove
    root = document.at_css('main') || document.at_css('article') || document.at_css('body')
    return '' if root.nil?

    text = ReverseMarkdown.convert(root, unknown_tags: :bypass, github_flavored: true).gsub('&nbsp;', ' ')
    text.gsub(/[[:blank:]]+/, ' ').gsub(/ ?\n ?/, "\n").gsub(/\n{3,}/, "\n\n").strip.truncate(AgentBotPage::CONTENT_LIMIT)
  end
end
