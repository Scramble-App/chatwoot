require 'rails_helper'

RSpec.describe MessageTranslations::OpenaiSettings do
  describe '.max_output_tokens' do
    def hook_with(settings)
      build(:integrations_hook, :openai, settings: { 'api_key' => 'openai-key' }.merge(settings))
    end

    it 'keeps a configured limit above 10 000 so reasoning models have room for the answer' do
      expect(described_class.max_output_tokens(hook_with('translation_max_output_tokens' => '100000'))).to eq(100_000)
    end

    it 'uses the default when no limit is configured' do
      expect(described_class.max_output_tokens(hook_with({}))).to eq(1200)
    end

    it 'raises a limit below 100 to 100' do
      expect(described_class.max_output_tokens(hook_with('translation_max_output_tokens' => '5'))).to eq(100)
    end
  end
end
