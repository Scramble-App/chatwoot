require 'rails_helper'

RSpec.describe DeveloperReports::ReportService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) do
    create(:contact, account: account, name: 'Maria K', email: 'maria@example.com', phone_number: '+37255512345',
                     custom_attributes: { 'plan' => 'gold' })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:openai_service) { instance_double(DeveloperReports::OpenaiReportService, perform: 'Report') }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow(DeveloperReports::OpenaiReportService).to receive(:new).and_return(openai_service)
  end

  context 'with the OpenAI integration' do
    before { create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-test' }) }

    it 'sends the conversation details and the messages with their times' do
      account.update!(reporting_timezone: 'Europe/Tallinn')
      conversation.update!(additional_attributes: {
                             'browser' => { 'browser_name' => 'Chrome', 'browser_version' => '129.0', 'platform_name' => 'macOS',
                                            'platform_version' => '14', 'device_name' => 'Macintosh' },
                             'browser_language' => 'de', 'referer' => 'https://app.example.com/invest'
                           })
      create_message('Payment failed: 3DS error', :incoming, created_at: Time.zone.parse('2026-10-14 15:30 UTC'))
      create_message('Please try again', :outgoing, created_at: Time.zone.parse('2026-10-14 15:35 UTC'))
      create_message('Checked the payment provider', :outgoing, created_at: Time.zone.parse('2026-10-14 15:40 UTC'), private_message: true)

      expect(described_class.new(conversation: conversation).perform).to eq('Report')

      expect(DeveloperReports::OpenaiReportService).to have_received(:new) do |args|
        expect(args[:context]).to include(
          'Times are in Europe/Tallinn.',
          "Conversation: ##{conversation.display_id} ", "/app/accounts/#{account.id}/conversations/#{conversation.display_id}",
          'Customer email: maria@example.com', 'Customer phone: +37255512345', 'Customer attributes: {"plan":"gold"}',
          'Customer browser: Chrome 129.0, macOS 14, Macintosh', 'Browser language: de',
          'Page the chat was opened on: https://app.example.com/invest',
          '[2026-10-14 18:30] Customer: Payment failed: 3DS error',
          '[2026-10-14 18:35] Agent reply to customer: Please try again',
          '[2026-10-14 18:40] Internal private note: Checked the payment provider'
        )
        expect(args[:images]).to eq([])
      end
    end

    it 'sends the newest screenshots of the customer and links every attachment' do
      stub_const("#{described_class}::IMAGE_LIMIT", 1)
      older = create_message('First screenshot', :incoming, created_at: 3.minutes.ago, attachment: 'avatar.png')
      newer = create_message('Second screenshot', :incoming, created_at: 2.minutes.ago, attachment: 'sample.png')
      create_message('The statement', :incoming, created_at: 1.minute.ago, attachment: 'sample.pdf')
      create_message('Our screenshot', :outgoing, created_at: Time.current, attachment: 'avatar.png')

      described_class.new(conversation: conversation).perform

      expect(DeveloperReports::OpenaiReportService).to have_received(:new) do |args|
        expect(args[:context]).to include("Attachment (image): #{older.attachments.first.file_url}", 'Attachment (file): ')
        expect(args[:images].pluck(:url)).to eq([newer.attachments.first.file_url])
        expect(args[:images].first[:data_url]).to start_with('data:image/png;base64,')
      end
    end

    it 'only links screenshots over the size limit' do
      stub_const("#{described_class}::IMAGE_BYTE_LIMIT", 10)
      message = create_message('Screenshot', :incoming, created_at: 1.minute.ago, attachment: 'avatar.png')

      described_class.new(conversation: conversation).perform

      expect(DeveloperReports::OpenaiReportService).to have_received(:new) do |args|
        expect(args[:context]).to include(message.attachments.first.file_url)
        expect(args[:images]).to be_empty
      end
    end

    it 'keeps the newest messages when the conversation is longer than the limit' do
      stub_const("#{described_class}::CONTEXT_CHARACTER_LIMIT", 60)
      create_message("An old question #{'a' * 30}", :incoming, created_at: 2.minutes.ago)
      create_message('Where is my money?', :incoming, created_at: 1.minute.ago)

      described_class.new(conversation: conversation).perform

      expect(DeveloperReports::OpenaiReportService).to have_received(:new) do |args|
        expect(args[:context]).to include('Customer: Where is my money?')
        expect(args[:context]).not_to include('An old question')
      end
    end

    it 'raises a controlled error when the conversation has no messages' do
      expect { described_class.new(conversation: conversation).perform }
        .to raise_error(described_class::Error, 'No conversation messages available to report')
    end
  end

  it 'raises a controlled error when the OpenAI integration is not configured' do
    create_message('Hola', :incoming, created_at: Time.current)

    expect { described_class.new(conversation: conversation).perform }
      .to raise_error(described_class::Error, 'OpenAI integration is not configured')
  end

  def create_message(content, message_type, created_at:, private_message: false, attachment: nil)
    message = build(:message, account: account, inbox: inbox, conversation: conversation, content: content,
                              message_type: message_type, private: private_message, created_at: created_at)
    if attachment
      pdf = attachment.end_with?('.pdf')
      message.attachments.new(account_id: account.id, file_type: pdf ? :file : :image)
             .file.attach(io: Rails.root.join('spec/assets', attachment).open, filename: attachment,
                          content_type: pdf ? 'application/pdf' : 'image/png')
    end
    message.save!
    message
  end
end
