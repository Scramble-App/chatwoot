# A report of a conversation for the IT support and development team, who investigate the customer's problem: who the
# customer is, the conversation with its times and attachment links, the customer's browser, and the screenshots the
# customer sent, which the model reads for error texts.
class DeveloperReports::ReportService
  class Error < StandardError; end

  MESSAGE_LIMIT = 500
  CONTEXT_CHARACTER_LIMIT = 40_000
  # The customer's newest screenshots are sent to the model; others are only linked in the context
  IMAGE_LIMIT = 4
  IMAGE_BYTE_LIMIT = 5.megabytes
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze

  pattr_initialize [:conversation!]

  def perform
    hook = MessageTranslations::OpenaiSettings.hook_for(conversation.account)
    raise Error, 'OpenAI integration is not configured' if hook.blank?
    raise Error, 'No conversation messages available to report' if context_messages.empty?

    DeveloperReports::OpenaiReportService.new(hook: hook, context: context_text, images: images).perform
  end

  private

  def context_text
    <<~TEXT
      Times are in #{time_zone.tzinfo.identifier}.

      Conversation details:
      #{conversation_details.join("\n")}

      Messages, oldest to newest:
      #{context_messages.map { |message| format_message(message) }.join("\n")}
    TEXT
  end

  def conversation_details
    [
      "Conversation: ##{conversation.display_id} #{conversation_url}",
      "Channel: #{conversation.inbox.name} (#{conversation.inbox.channel_type.demodulize})",
      "Started: #{format_time(conversation.created_at)}",
      *customer_details,
      ("Labels: #{conversation.label_list.join(', ')}" if conversation.label_list.present?),
      *browser_details
    ].compact
  end

  def customer_details
    contact = conversation.contact
    [
      "Customer: #{contact.name}",
      ("Customer email: #{contact.email}" if contact.email.present?),
      ("Customer phone: #{contact.phone_number}" if contact.phone_number.present?),
      ("Customer attributes: #{contact.custom_attributes.to_json}" if contact.custom_attributes.present?)
    ]
  end

  # The website widget records the customer's browser and the page the chat was opened on
  def browser_details
    attributes = conversation.additional_attributes || {}
    browser = attributes['browser'] || {}
    parts = [
      [browser['browser_name'], browser['browser_version']].compact_blank.join(' '),
      [browser['platform_name'], browser['platform_version']].compact_blank.join(' '),
      browser['device_name']
    ].compact_blank

    [
      ("Customer browser: #{parts.join(', ')}" if parts.any?),
      ("Browser language: #{attributes['browser_language']}" if attributes['browser_language'].present?),
      ("Page the chat was opened on: #{attributes['referer']}" if attributes['referer'].present?)
    ]
  end

  # The newest messages that fit the limit, oldest to newest, so the latest details are never dropped
  def context_messages
    @context_messages ||= begin
      selected = []
      character_count = 0

      messages.each do |message|
        formatted = format_message(message)
        next if formatted.blank?
        break if character_count + formatted.length > CONTEXT_CHARACTER_LIMIT

        selected.unshift(message)
        character_count += formatted.length
      end

      selected
    end
  end

  # Newest first
  def messages
    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .where(
                  '(messages.message_type = :incoming AND messages.private = :public_message) OR messages.message_type = :outgoing',
                  incoming: Message.message_types[:incoming],
                  outgoing: Message.message_types[:outgoing],
                  public_message: false
                )
                .includes(attachments: { file_attachment: :blob })
                .reorder(created_at: :desc, id: :desc)
                .limit(MESSAGE_LIMIT)
  end

  def format_message(message)
    content = MessageTranslations::OpenaiTranslationService.source_text_for(message)
    attachments = message.attachments.select { |attachment| attachment.file.attached? }
    return if content.blank? && attachments.empty?

    lines = ["[#{format_time(message.created_at)}] #{speaker(message)}: #{content}"]
    lines += attachments.map { |attachment| "Attachment (#{attachment.file_type}): #{attachment.file_url}" }
    lines.join("\n").truncate(CONTEXT_CHARACTER_LIMIT)
  end

  def speaker(message)
    return 'Customer' if message.incoming?
    return 'Internal private note' if message.private?

    'Agent reply to customer'
  end

  # A screenshot that is gone from storage is left out; its link stays in the context
  def images
    image_attachments.filter_map do |attachment|
      data = attachment.file.blob.open { |file| Base64.strict_encode64(file.read) }
      { url: attachment.file_url, data_url: "data:#{attachment.file.content_type};base64,#{data}" }
    rescue ActiveStorage::FileNotFoundError
      nil
    end
  end

  def image_attachments
    context_messages.select(&:incoming?).flat_map(&:attachments).select { |attachment| readable_image?(attachment) }.last(IMAGE_LIMIT)
  end

  def readable_image?(attachment)
    attachment.image? && attachment.file.attached? &&
      IMAGE_CONTENT_TYPES.include?(attachment.file.content_type) && attachment.file.byte_size <= IMAGE_BYTE_LIMIT
  end

  def conversation_url
    Rails.application.routes.url_helpers.app_account_conversation_url(account_id: conversation.account_id, id: conversation.display_id)
  end

  def format_time(time)
    time.in_time_zone(time_zone).strftime('%Y-%m-%d %H:%M')
  end

  def time_zone
    @time_zone ||= ActiveSupport::TimeZone[conversation.account.reporting_timezone.to_s] ||
                   ActiveSupport::TimeZone[AccountUser::DEFAULT_SCHEDULE_TIMEZONE]
  end
end
