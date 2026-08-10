class AiGenerations::BroadcastService
  pattr_initialize [:generation!, :event_name!]

  def perform
    token = generation.user&.pubsub_token
    return if token.blank?

    ActionCableBroadcastJob.perform_later([token], event_name, payload)
  end

  private

  def payload
    generation.push_event_data.merge(
      account_id: generation.account_id,
      conversation_id: generation.conversation.display_id
    )
  end
end
