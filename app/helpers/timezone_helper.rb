module TimezoneHelper
  # Reports use the account's reporting timezone when it is set, so every viewer sees the same days and hours.
  # Only an IANA timezone counts, since the dashboard works with those; a Rails name such as "Tallinn" is ignored on both sides.
  def account_report_timezone(account)
    timezone = account&.reporting_timezone
    timezone if timezone.present? && TZInfo::Timezone.all_identifiers.include?(timezone)
  end

  def timezone_name_from_params(timezone, offset)
    return timezone if timezone.present? && ActiveSupport::TimeZone[timezone].present?

    timezone_name_from_offset(offset)
  end

  # ActiveSupport TimeZone is not aware of the current time, so ActiveSupport::Timezone[offset]
  # would return the timezone without considering day light savings. To get the correct timezone,
  # this method uses zone.now.utc_offset for comparison as referenced in the issues below
  #
  # https://github.com/rails/rails/pull/22243
  # https://github.com/rails/rails/issues/21501
  # https://github.com/rails/rails/issues/7297
  def timezone_name_from_offset(offset)
    return 'UTC' if offset.blank?

    offset_in_seconds = offset.to_f * 3600
    matching_zone = ActiveSupport::TimeZone.all.find do |zone|
      zone.now.utc_offset == offset_in_seconds
    end

    return matching_zone.name if matching_zone
  end
end
