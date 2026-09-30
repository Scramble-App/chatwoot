# Turns an agent's recorded dictation into reply text with the OpenAI transcription API.
# The recording is only forwarded to OpenAI and never stored.
class Dictations::OpenaiTranscriptionService
  class Error < StandardError; end

  DEFAULT_MODEL = 'gpt-transcribe'.freeze
  # OpenAI rejects larger files
  MAX_AUDIO_SIZE = 25.megabytes

  pattr_initialize [:account!, :user!, :audio!]

  def perform
    validate!

    response = post_audio
    parsed_body = parse_response_body(response.body)
    raise Error, parsed_body.dig('error', 'message').presence || "OpenAI transcription failed with HTTP #{response.status}" unless response.success?

    parsed_body['text'].to_s.strip.presence || raise(Error, 'No speech was recognized in the recording')
  rescue Faraday::Error => e
    raise Error, "OpenAI transcription failed: #{e.message}"
  end

  private

  def validate!
    raise Error, 'Audio recording is required' unless audio.is_a?(ActionDispatch::Http::UploadedFile)
    raise Error, 'The recording is too long, please dictate a shorter reply' if audio.size > MAX_AUDIO_SIZE
    raise Error, 'OpenAI integration is not configured' if hook.blank?
  end

  def post_audio
    connection.post("#{Integrations::Openai::KeyValidator.api_base}/audio/transcriptions", request_params) do |request|
      request.headers['Authorization'] = "Bearer #{hook.settings['api_key']}"
    end
  end

  def hook
    @hook ||= MessageTranslations::OpenaiSettings.hook_for(account)
  end

  # language and prompt work with every transcription model; the prompt carries the terms to spell correctly
  def request_params
    {
      model: hook.settings['dictation_model'].presence || DEFAULT_MODEL,
      file: Faraday::Multipart::FilePart.new(audio.tempfile, audio.content_type, audio.original_filename),
      language: language,
      prompt: hook.settings['dictation_terms'].presence
    }.compact
  end

  # The agent's operator translation language (e.g. "ru" or "pt_BR") as an ISO-639-1 code
  def language
    account.account_users.find_by(user: user)&.translation_locale.to_s.split(/[_-]/).first.presence
  end

  def parse_response_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def connection
    Faraday.new do |faraday|
      faraday.request :multipart
      faraday.options.timeout = MessageTranslations::OpenaiResponsesClient::WEB_REQUEST_TIMEOUT_SECONDS
      faraday.options.open_timeout = MessageTranslations::OpenaiResponsesClient::CONNECT_TIMEOUT_SECONDS
    end
  end
end
