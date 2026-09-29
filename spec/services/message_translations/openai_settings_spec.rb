require 'rails_helper'

RSpec.describe MessageTranslations::OpenaiSettings do
  def hook_with(settings)
    build(:integrations_hook, :openai, settings: { 'api_key' => 'openai-key' }.merge(settings))
  end

  describe '.model' do
    it 'ignores whitespace around the configured model, which OpenAI would reject' do
      expect(described_class.model(hook_with('translation_model' => " gpt-6-sol\n"))).to eq('gpt-6-sol')
    end

    it 'uses the default model when only whitespace is configured' do
      expect(described_class.model(hook_with('translation_model' => '  '))).to eq(described_class::DEFAULT_MODEL)
    end
  end

  describe '.max_output_tokens' do
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
