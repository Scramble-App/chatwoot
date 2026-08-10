class AiGenerations::KnowledgeAnswerJob < AiGenerations::BaseJob
  MODEL = AiGenerations::KnowledgeAnswer
  EVENT = Events::Types::KNOWLEDGE_ANSWER_UPDATED
  EXPECTED_ERRORS = [
    'KnowledgeAnswers::AnswerService::Error',
    'KnowledgeAnswers::OpenaiAnswerService::Error',
    'Integrations::OnyxMcp::Client::Error'
  ].freeze

  private

  def generate(generation)
    KnowledgeAnswers::AnswerService.new(
      conversation: generation.conversation,
      user: generation.user
    ).perform
  end
end
