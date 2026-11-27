require 'rails_helper'
require 'rake'

RSpec.describe 'ai_agent:evaluate', type: :task do
  include AiAgentOpenaiHelpers

  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account) }
  let(:out_dir) { Dir.mktmpdir }
  let(:out) { File.join(out_dir, 'report.json') }
  let(:task) { Rake::Task['ai_agent:evaluate'] }

  before do
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    Rake.application.rake_require('tasks/ai_agent', [Rails.root.join('lib').to_s]) unless Rake::Task.task_defined?('ai_agent:evaluate')
    task.reenable
    create_ai_agent_openai_hook(account)
    create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', alternative_questions: 'How does it work?')
    stub_openai_responses(openai_reply(kind: 'answer', entry_keys: ['KB-001']))
  end

  after { FileUtils.remove_entry(out_dir) }

  it 'writes the JSON report to OUT and prints the progress and the summary' do
    with_modified_env(OUT: out, INPUT_PRICE_PER_1M: '1', OUTPUT_PRICE_PER_1M: '4') do
      expect { task.invoke(agent_bot.id.to_s) }
        .to output(%r{\[1/1\] phrasing KB-001/1: ok.*Correct entry\s+1/1 \(100.0%\).*Estimated cost\s+\$0\.0002.*JSON report: #{out}}m).to_stdout
    end

    expect(JSON.parse(File.read(out))['metrics']['correct_entry']).to eq('passed' => 1, 'total' => 1, 'rate' => 1.0)
  end

  it 'evaluates only AI agent bots' do
    webhook_bot = create(:agent_bot, account: account)

    expect { task.invoke(webhook_bot.id.to_s) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
