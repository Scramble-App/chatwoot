require 'rails_helper'

RSpec.describe CustomerIdentityListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:event) { Events::Base.new(:'message.created', Time.zone.now, message: message) }

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  it 'enqueues the email suggestion job for created messages' do
    expect(CustomerIdentity::MessageEmailSuggestionJob).to receive(:perform_later).with(message.id)

    listener.message_created(event)
  end
end
