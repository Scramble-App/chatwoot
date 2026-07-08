require 'rails_helper'

RSpec.describe CustomerIdentity::EmailExtractor do
  it 'extracts and normalizes an email from plain text with punctuation' do
    emails = described_class.new(content: 'Here is my email: User.Name+crm@Example.COM, thanks.').perform

    expect(emails).to eq(['user.name+crm@example.com'])
  end

  it 'extracts multiple unique emails in message order' do
    emails = described_class.new(
      content: 'first@example.com and SECOND@example.com; first@example.com again'
    ).perform

    expect(emails).to eq(%w[first@example.com second@example.com])
  end

  it 'ignores invalid email-like text' do
    emails = described_class.new(content: 'invalid@localhost and missing-at.example.com').perform

    expect(emails).to be_empty
  end
end
