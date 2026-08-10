class AiGenerations::BaseJob < ApplicationJob
  queue_as :high

  def perform(generation_id)
    generation = self.class::MODEL.find_by(id: generation_id)
    return if generation.blank?

    run(generation)
  end

  private

  def run(generation)
    generation.mark_running!
    broadcast(generation)

    generation.complete!(generate(generation))
    broadcast(generation)
  rescue StandardError => e
    generation.fail!(error_message_for(e))
    broadcast(generation)
    Rails.logger.error("[ai-generation] #{self.class.name} #{e.class}: #{e.message}")
  end

  # Наследник возвращает сгенерированный текст. Исключения обрабатываются в run.
  def generate(_generation)
    raise NotImplementedError
  end

  def broadcast(generation)
    AiGenerations::BroadcastService.new(generation: generation, event_name: self.class::EVENT).perform
  end

  # Ожидаемые ошибки сервисов показываем оператору как есть, остальное скрываем за общим текстом.
  def error_message_for(error)
    self.class::EXPECTED_ERRORS.include?(error.class.name) ? error.message : I18n.t('ai_generations.generic_error')
  end
end
