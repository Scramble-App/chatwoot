require 'rails_helper'

RSpec.describe KnowledgeAnswers::OnyxSettings do
  def hook_with(settings)
    build(:integrations_hook, :onyx_mcp, settings: { 'mcp_url' => 'https://cloud.onyx.app/mcp', 'api_token' => 'onyx-token' }.merge(settings))
  end

  describe '.source_types' do
    it 'normalizes the configured list to the lowercase names Onyx expects' do
      expect(described_class.source_types(hook_with('source_types' => ' Confluence, JIRA,,web '))).to eq(%w[confluence jira web])
    end
  end

  describe '.search_question_instructions' do
    it 'returns the configured instructions' do
      hook = hook_with('query_template' => ' Use Group A and Group B. ')

      expect(described_class.search_question_instructions(hook)).to eq('Use Group A and Group B.')
    end

    it 'ignores a query template saved before OpenAI wrote the search question' do
      expect(described_class.search_question_instructions(hook_with('query_template' => 'Question: {{conversation_context}}'))).to be_nil
    end

    it 'returns nothing when no instructions are configured' do
      expect(described_class.search_question_instructions(hook_with({}))).to be_nil
    end
  end
end
