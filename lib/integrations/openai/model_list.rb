module Integrations::Openai::ModelList
  TIMEOUT_SECONDS = 5

  # Model IDs available to the API key, newest first; empty when OpenAI cannot be reached.
  def self.fetch(api_key)
    connection = Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end

    response = connection.get("#{Integrations::Openai::KeyValidator.api_base}/models") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
    end
    return [] unless response.success?

    JSON.parse(response.body).fetch('data', []).sort_by { |model| -model['created'].to_i }.pluck('id')
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("[openai-model-list] #{e.class}: #{e.message}")
    []
  end
end
