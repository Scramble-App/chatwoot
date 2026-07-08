require 'rails_helper'

RSpec.describe MessageTranslationListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Hola') }
  let(:event) { Events::Base.new(:'message.created', Time.zone.now, message: message) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:inbox_member, inbox: inbox, user: agent)
    agent.account_users.find_by(account: account).update!(translation_locale: 'en')
    create(
      :integrations_hook,
      :openai,
      account: account,
      settings: {
        'api_key' => 'sk-test',
        'translation_enabled' => true,
        'auto_translate_incoming' => true
      }
    )
  end

  it 'enqueues translation jobs for configured operator languages' do
    expect(MessageTranslations::AutoTranslateJob).to receive(:perform_later).with(message.id, 'en')

    listener.message_created(event)
  end

  it 'does not enqueue jobs when automatic translation is disabled' do
    account.hooks.find_by(app_id: 'openai').update!(
      settings: { 'api_key' => 'sk-test', 'translation_enabled' => true, 'auto_translate_incoming' => false }
    )

    expect(MessageTranslations::AutoTranslateJob).not_to receive(:perform_later)

    listener.message_created(event)
  end
end
