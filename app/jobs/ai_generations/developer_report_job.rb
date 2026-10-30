class AiGenerations::DeveloperReportJob < AiGenerations::BaseJob
  MODEL = AiGenerations::DeveloperReport
  EVENT = Events::Types::DEVELOPER_REPORT_UPDATED
  EXPECTED_ERRORS = [
    'DeveloperReports::ReportService::Error',
    'DeveloperReports::OpenaiReportService::Error',
    'MessageTranslations::OpenaiResponsesClient::Error'
  ].freeze

  private

  def generate(generation)
    DeveloperReports::ReportService.new(conversation: generation.conversation).perform
  end
end
