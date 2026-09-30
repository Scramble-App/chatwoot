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

  describe '.query_for' do
    it 'inserts the conversation as typed, including backslash sequences' do
      hook = hook_with('query_template' => 'Question: {{conversation_context}}')

      expect(described_class.query_for(hook, 'Customer: path C:\\0\\& fails')).to eq('Question: Customer: path C:\\0\\& fails')
    end
  end
end
