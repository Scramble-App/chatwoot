# Runs the tool calls of one AI agent reply. open_page only reads, so it runs here; save_contact and hand_off are checked
# here, then go to the executor, which acts on them (AiAgents::ReplyService) or records them (AiAgents::Evaluation).
class AiAgents::ToolRunner
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  CONTACT_DETAIL_LIMIT = 255

  # The tool calls so far: { name:, arguments:, error: }
  attr_reader :calls

  # pages: the pages the agent can open; executor: called with 'save_contact' or 'hand_off' and the checked arguments,
  # returns the tool result
  def initialize(pages:, executor:)
    @pages = pages
    @executor = executor
    @calls = []
  end

  def handed_off?
    !@hand_off.nil?
  end

  # The tool result for the model
  def run(call)
    arguments = JSON.parse(call['arguments'].to_s)
    result = case call['name']
             when 'open_page' then open_page(arguments)
             when 'save_contact' then save_contact(arguments)
             when 'hand_off' then hand_off(arguments)
             else { error: "There is no tool named #{call['name']}" }
             end
    @calls << { name: call['name'], arguments: arguments, error: result[:error] }.compact
    result
  rescue JSON::ParserError
    { error: 'The arguments are not valid JSON' }
  end

  private

  def open_page(arguments)
    page = @pages.find_by(id: arguments['page_id'])
    return { error: 'There is no page with this id. Use an id from PAGES.' } unless page

    { title: page.title, url: page.url, content: page.content }
  end

  def save_contact(arguments)
    details = {
      'name' => arguments['name'].to_s.squish.truncate(CONTACT_DETAIL_LIMIT).presence,
      'company' => arguments['company'].to_s.squish.truncate(CONTACT_DETAIL_LIMIT).presence,
      'email' => arguments['email'].to_s.strip.downcase.presence
    }.compact
    return { error: 'There is nothing to save' } if details.empty?
    return { error: 'The email address is not valid. Ask the visitor to check it.' } if details['email'] && !valid_email?(details['email'])

    @executor.call('save_contact', details)
  end

  def valid_email?(email)
    email.length <= CONTACT_DETAIL_LIMIT && email.match?(EMAIL_FORMAT)
  end

  # A reply hands off once; a second call gets the result of the first
  def hand_off(arguments)
    reason = AiAgents::Prompt::HANDOFF_REASONS.include?(arguments['reason']) ? arguments['reason'] : 'other'
    details = {
      'reason' => reason,
      'summary' => arguments['summary'].to_s.strip.presence,
      'unanswered_question' => arguments['unanswered_question'].to_s.squish.presence
    }
    @hand_off ||= @executor.call('hand_off', details)
  end
end
