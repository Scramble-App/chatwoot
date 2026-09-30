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

  describe '.search_question_model' do
    it 'uses the translation model when no own model is configured' do
      expect(described_class.search_question_model(hook_with('translation_model' => 'gpt-6-sol'))).to eq('gpt-6-sol')
    end

    it 'uses its own model when configured' do
      hook = hook_with('translation_model' => 'gpt-6-sol', 'search_question_model' => ' gpt-6-luna ')

      expect(described_class.search_question_model(hook)).to eq('gpt-6-luna')
    end
  end

  describe '.search_question_reasoning_effort' do
    it 'is low when not configured, whatever the translation effort' do
      expect(described_class.search_question_reasoning_effort(hook_with('translation_reasoning_effort' => 'max'))).to eq('low')
    end

    it 'uses the configured effort' do
      expect(described_class.search_question_reasoning_effort(hook_with('search_question_reasoning_effort' => ' High '))).to eq('high')
    end
  end

  describe '.service_tier' do
    it 'passes the configured tier through in lowercase' do
      expect(described_class.service_tier(hook_with('translation_service_tier' => ' Priority '))).to eq('priority')
    end

    it 'sends no tier when none is configured, so the OpenAI project setting applies' do
      expect(described_class.service_tier(hook_with({}))).to be_nil
      expect(described_class.apply_model_options!({}, hook_with({}))).not_to have_key(:service_tier)
    end

    it 'ignores a value that is not a tier name' do
      expect(described_class.service_tier(hook_with('translation_service_tier' => 'fast; drop'))).to be_nil
    end

    it 'adds the tier to the request options' do
      expect(described_class.apply_model_options!({}, hook_with('translation_service_tier' => 'flex'))).to include(service_tier: 'flex')
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
