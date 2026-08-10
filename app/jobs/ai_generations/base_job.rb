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

    content = generate(generation)
    return if dismissed?(generation)

    generation.complete!(content)
    broadcast(generation)
  rescue StandardError => e
    Rails.logger.error("[ai-generation] #{self.class.name} #{e.class}: #{e.message}")
    return if dismissed?(generation)

    generation.fail!(error_message_for(e))
    broadcast(generation)
  end

  # The operator dismissed the generation while the job was running, so the result is no longer wanted.
  def dismissed?(generation)
    !self.class::MODEL.exists?(generation.id)
  end

  # Subclasses return the generated text. Exceptions are handled in run.
  def generate(_generation)
    raise NotImplementedError
  end

  def broadcast(generation)
    AiGenerations::BroadcastService.new(generation: generation, event_name: self.class::EVENT).perform
  end

  # Expected service errors are shown to the operator as they are; anything else hides behind a generic message.
  def error_message_for(error)
    self.class::EXPECTED_ERRORS.include?(error.class.name) ? error.message : I18n.t('ai_generations.generic_error')
  end
end
