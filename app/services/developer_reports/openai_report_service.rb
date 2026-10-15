# Asks OpenAI for the developer report: the conversation context as text, then each screenshot the customer sent.
class DeveloperReports::OpenaiReportService
  class Error < StandardError; end

  # A report runs longer than a summary, and reasoning tokens count toward the limit too
  MIN_OUTPUT_TOKENS = 4000

  pattr_initialize [:hook!, :context!, :images!]

  def perform
    text = MessageTranslations::OpenaiResponsesClient.output_text(make_request)
    text.presence || raise(Error, 'OpenAI returned an empty developer report')
  end

  private

  def make_request
    response, parsed_body = MessageTranslations::OpenaiResponsesClient.new(api_key: hook.settings['api_key']).create(request_body)
    return parsed_body if response.success?

    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI developer report failed with HTTP #{response.status}"
  end

  def request_body
    body = {
      model: MessageTranslations::OpenaiSettings.model(hook),
      instructions: MessageTranslations::OpenaiSettings.developer_report_instructions(hook),
      input: [{ role: 'user', content: input_content }],
      max_output_tokens: [MessageTranslations::OpenaiSettings.max_output_tokens(hook), MIN_OUTPUT_TOKENS].max,
      store: false
    }

    MessageTranslations::OpenaiSettings.apply_model_options!(body, hook)
  end

  # Each screenshot follows a line with its attachment link, so the report can tell which one a detail comes from
  def input_content
    [{ type: 'input_text', text: context }] + images.flat_map do |image|
      [
        { type: 'input_text', text: "Screenshot #{image[:url]}:" },
        { type: 'input_image', image_url: image[:data_url], detail: 'high' }
      ]
    end
  end
end
