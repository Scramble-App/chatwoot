# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_assignment_event do
    conversation
    account { conversation.account }
    inbox { conversation.inbox }
    team { conversation.team }
    event_type { 'assigned' }
    source { 'manual' }
    occurred_at { Time.current }
  end
end
