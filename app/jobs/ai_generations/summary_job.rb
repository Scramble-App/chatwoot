class AiGenerations::SummaryJob < AiGenerations::BaseJob
  MODEL = AiGenerations::Summary
  EVENT = Events::Types::CONVERSATION_SUMMARY_UPDATED
  EXPECTED_ERRORS = [
    'ConversationSummaries::SummaryService::Error',
    'ConversationSummaries::OpenaiSummaryService::Error'
  ].freeze

  private

  def generate(generation)
    ConversationSummaries::SummaryService.new(
      conversation: generation.conversation,
      user: generation.user
    ).perform
  end
end
