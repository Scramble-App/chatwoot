class AiGenerations::PreparedReplyJob < AiGenerations::BaseJob
  MODEL = AiGenerations::PreparedReply
  EVENT = Events::Types::PREPARED_REPLY_UPDATED
  EXPECTED_ERRORS = [
    'ReplyPreparations::PrepareReplyService::Error',
    'ReplyPreparations::OpenaiPrepareReplyService::Error'
  ].freeze

  private

  def generate(generation)
    ReplyPreparations::PrepareReplyService.new(
      conversation: generation.conversation,
      content: generation.source_content
    ).perform
  end
end
