# frozen_string_literal: true

namespace :reporting_events do
  desc 'Recalculate the business time of past reporting events from agent shifts. ' \
       'Usage: rake "reporting_events:recalculate_business_time[ACCOUNT_ID]" DRY_RUN=true SINCE=2026-01-01'
  task :recalculate_business_time, [:account_id] => :environment do |_task, args|
    account = Account.find(args.fetch(:account_id))
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'false'))
    since = ENV['SINCE'].present? ? Time.zone.parse(ENV.fetch('SINCE')) : nil

    service = ReportingEvents::BusinessTimeRecalculationService.new(account: account, since: since, dry_run: dry_run).perform

    puts "#{dry_run ? 'Would update' : 'Updated'} the business time of #{service.changed_count} reporting events of account #{account.id}"
  end
end
