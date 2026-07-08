class CustomerIdentity::EmailExtractor
  EMAIL_CANDIDATE_REGEX = /[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i

  pattr_initialize [:content!]

  def perform
    content.to_s.scan(EMAIL_CANDIDATE_REGEX)
           .map(&:downcase)
           .uniq
           .grep(Devise.email_regexp)
  end
end
