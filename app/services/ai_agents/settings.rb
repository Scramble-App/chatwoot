# Reads the bot_config of an AI agent bot, where a blank value means the default. A blank model means the model of the
# account's OpenAI integration, so #model returns nil and callers resolve it with MessageTranslations::OpenaiSettings.model(hook).
class AiAgents::Settings
  KEYS = %w[model reasoning_effort tone_of_voice instructions handoff_team_id max_replies_per_conversation fallback_message].freeze
  TEXT_LIMITS = { 'model' => 255, 'reasoning_effort' => 255, 'tone_of_voice' => 5_000, 'instructions' => 10_000, 'fallback_message' => 1_000 }.freeze
  # Same names as MessageTranslations::OpenaiSettings accepts; OpenaiResponsesClient drops an effort the model rejects
  REASONING_EFFORT_FORMAT = /\A[a-z_]+\z/
  MAX_REPLIES_RANGE = (1..200)
  DEFAULT_REASONING_EFFORT = 'low'.freeze
  DEFAULT_MAX_REPLIES_PER_CONVERSATION = 30

  # The model default is left out: it is the account's OpenAI integration model
  def self.defaults
    {
      reasoning_effort: DEFAULT_REASONING_EFFORT,
      tone_of_voice: AiAgents::Defaults::TONE_OF_VOICE,
      instructions: AiAgents::Defaults::INSTRUCTIONS,
      max_replies_per_conversation: DEFAULT_MAX_REPLIES_PER_CONVERSATION,
      fallback_message: AiAgents::Defaults::FALLBACK_MESSAGE
    }
  end

  def initialize(agent_bot)
    @agent_bot = agent_bot
    @config = (agent_bot.bot_config || {}).stringify_keys
  end

  def model
    text('model')
  end

  def reasoning_effort
    text('reasoning_effort')&.downcase || DEFAULT_REASONING_EFFORT
  end

  def tone_of_voice
    text('tone_of_voice') || AiAgents::Defaults::TONE_OF_VOICE
  end

  def instructions
    text('instructions') || AiAgents::Defaults::INSTRUCTIONS
  end

  def handoff_team_id
    integer('handoff_team_id')
  end

  # nil without a team, or when the team was deleted after the bot was saved
  def handoff_team
    @agent_bot.account&.teams&.find_by(id: handoff_team_id) if handoff_team_id
  end

  def max_replies_per_conversation
    integer('max_replies_per_conversation') || DEFAULT_MAX_REPLIES_PER_CONVERSATION
  end

  def fallback_message
    text('fallback_message') || AiAgents::Defaults::FALLBACK_MESSAGE
  end

  # Unknown keys are rejected, not dropped
  def validation_errors
    [unknown_keys_error, *text_errors, reasoning_effort_error, max_replies_error, handoff_team_error].compact
  end

  private

  def text(key)
    @config[key].to_s.strip.presence
  end

  # Integer-like strings count, as the dashboard sends the bot as form data
  def integer(key)
    Integer(@config[key].to_s, 10, exception: false)
  end

  def error(type, **)
    I18n.t("errors.agent_bots.bot_config.#{type}", **)
  end

  def unknown_keys_error
    unknown_keys = @config.keys - KEYS
    error(:unknown_keys, keys: unknown_keys.join(', ')) if unknown_keys.any?
  end

  def text_errors
    TEXT_LIMITS.filter_map do |key, limit|
      value = @config[key]
      error(:text, key: key, count: limit) if value.present? && !(value.is_a?(String) && value.length <= limit)
    end
  end

  def reasoning_effort_error
    effort = @config['reasoning_effort']
    return unless effort.is_a?(String) && effort.present?

    error(:invalid, key: 'reasoning_effort') unless effort.strip.downcase.match?(REASONING_EFFORT_FORMAT)
  end

  def max_replies_error
    return if @config['max_replies_per_conversation'].blank? || MAX_REPLIES_RANGE.cover?(integer('max_replies_per_conversation'))

    error(:range, key: 'max_replies_per_conversation', min: MAX_REPLIES_RANGE.min, max: MAX_REPLIES_RANGE.max)
  end

  def handoff_team_error
    error(:team, key: 'handoff_team_id') if @config['handoff_team_id'].present? && handoff_team.nil?
  end
end
