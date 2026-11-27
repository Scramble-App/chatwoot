require 'rails_helper'

RSpec.describe AiAgents::KnowledgeFormatter do
  def entry(**attributes)
    build(:agent_bot_knowledge_entry, short_answer: nil, answer: nil, **attributes)
  end

  it 'writes each entry as a key line and its non-blank answers, one blank line apart' do
    entries = [
      entry(key: 'KB-021', category: 'Pricing', question: 'How is my monthly repayment calculated?',
            short_answer: 'It goes to the principal.', answer: 'Every repayment goes to the principal.', selling_point: 'No interest.'),
      entry(key: 'KB-022', category: 'Pricing', question: 'Is there a fee?', short_answer: 'One flat fee.')
    ]

    expect(described_class.new(entries).to_s).to eq(<<~TEXT.chomp)
      #KB-021 Pricing | How is my monthly repayment calculated?
      Summary: It goes to the principal.
      Details: Every repayment goes to the principal.
      Selling point: No interest.

      #KB-022 Pricing | Is there a fee?
      Summary: One flat fee.
    TEXT
  end

  it 'leaves out a blank category' do
    expect(described_class.new([entry(key: 'KB-001', category: ' ', question: 'What is it?', answer: 'A sample.')]).to_s)
      .to eq("#KB-001 | What is it?\nDetails: A sample.")
  end

  it 'sorts by category, then by key number' do
    entries = [
      entry(key: 'KB-100', category: 'Billing', question: 'Q100?', answer: 'A.'),
      entry(key: 'KB-9', category: 'Billing', question: 'Q9?', answer: 'A.'),
      entry(key: 'KB-001', category: 'Onboarding', question: 'Q1?', answer: 'A.'),
      entry(key: 'CUSTOM', category: 'Billing', question: 'Custom?', answer: 'A.')
    ]

    keys = described_class.new(entries).to_s.scan(/^#(\S+)/).flatten

    expect(keys).to eq(%w[KB-9 KB-100 CUSTOM KB-001])
  end

  it 'keeps a field on its lines when it has blank lines inside' do
    text = described_class.new([entry(key: 'KB-002', question: "Two\nlines?", answer: "First paragraph.\r\n\r\n\nSecond paragraph.")]).to_s

    expect(text).to eq("#KB-002 | Two lines?\nDetails: First paragraph.\nSecond paragraph.")
  end
end
