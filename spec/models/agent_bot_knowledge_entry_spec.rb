require 'rails_helper'

RSpec.describe AgentBotKnowledgeEntry do
  let(:agent_bot) { create(:agent_bot, :ai_agent) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot) }
    it { is_expected.to have_many(:questions).class_name('AgentBotKnowledgeQuestion').dependent(:delete_all) }
  end

  describe 'validations' do
    it { is_expected.to define_enum_for(:status).with_values(draft: 0, published: 1, needs_answer: 2) }
    it { is_expected.to validate_presence_of(:question) }
    it { is_expected.to validate_length_of(:question).is_at_most(2_000) }
    it { is_expected.to validate_length_of(:key).is_at_most(255) }
    it { is_expected.to validate_length_of(:category).is_at_most(255) }
    it { is_expected.to validate_length_of(:frequency).is_at_most(255) }
    it { is_expected.to validate_length_of(:alternative_questions).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:short_answer).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:answer).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:selling_point).is_at_most(10_000) }

    it 'starts as a draft that was never asked' do
      entry = described_class.new

      expect(entry).to be_draft
      expect(entry.asked_count).to eq(0)
    end

    it 'rejects a blank or unknown status instead of raising' do
      ['archived', '', nil].each do |status|
        entry = build(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: status)

        expect(entry).not_to be_valid, "expected #{status.inspect} to be rejected"
        expect(entry.errors[:status]).to eq(['is not included in the list'])
      end
    end

    it 'needs an answer or a short answer to be published' do
      entry = build(:agent_bot_knowledge_entry, agent_bot: agent_bot, answer: '', short_answer: nil)

      expect(entry).not_to be_valid
      expect(entry.errors.full_messages).to include('Answer or short answer is required to publish the entry')
    end

    it 'publishes an entry with only a short or only a detailed answer' do
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, answer: nil)).to be_valid
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, short_answer: nil)).to be_valid
    end

    it 'keeps drafts and unanswered questions without an answer' do
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :draft, answer: nil, short_answer: nil)).to be_valid
      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer, answer: nil, short_answer: nil)).to be_valid
    end

    it 'takes the account from the bot when blank' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, account: nil)

      expect(entry.account).to eq(agent_bot.account)
    end

    it 'trims the texts and stores blank ones as nil' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, category: " Pricing \n", frequency: '  ', question: "\nAre there fees?\n",
                                                 alternative_questions: "Any fees?\nIs it free?\n\n", short_answer: ' No. ',
                                                 answer: "First line.\n\nSecond line.\n", selling_point: '')

      expect(entry.reload).to have_attributes(
        category: 'Pricing', frequency: nil, question: 'Are there fees?', alternative_questions: "Any fees?\nIs it free?",
        short_answer: 'No.', answer: "First line.\n\nSecond line.", selling_point: nil
      )
    end
  end

  describe 'key' do
    def create_entry(key: nil)
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: key)
    end

    it 'starts the knowledge base of a bot at KB-001' do
      expect(create_entry.key).to eq('KB-001')
    end

    it 'takes the next number after the highest KB- key of the bot' do
      create_entry(key: 'KB-012')
      create_entry(key: 'KB-7')
      create_entry(key: 'FAQ-99')
      create_entry(key: 'KB-90a')
      create(:agent_bot_knowledge_entry, key: 'KB-500')

      expect(create_entry.key).to eq('KB-013')
    end

    it 'uses at least 3 digits and more when the numbers grow' do
      create_entry(key: 'KB-9')
      expect(create_entry.key).to eq('KB-010')

      create_entry(key: 'KB-999')
      expect(create_entry.key).to eq('KB-1000')
    end

    it 'assigns a key when the given one is blank' do
      create_entry(key: 'KB-004')

      expect(create_entry(key: '  ').key).to eq('KB-005')
    end

    it 'keeps a given key' do
      expect(create_entry(key: 'PRICING-1').key).to eq('PRICING-1')
    end

    it 'trims a given key and keeps its case' do
      expect(create_entry(key: " KB-050 \n").key).to eq('KB-050')
      expect(create_entry(key: 'kb-052').key).to eq('kb-052')
    end

    it 'trims non-breaking and other Unicode spaces around a given key' do
      expect(create_entry(key: "\u00A0KB-056\u00A0").key).to eq('KB-056')
      expect(create_entry(key: "KB-057\u3000").key).to eq('KB-057')
    end

    it 'rejects whitespace inside a key' do
      ['KB 053', "KB-\n054", "KB-\t055", "KB\u00A0058"].each do |key|
        entry = build(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: key)

        expect(entry).not_to be_valid, "expected #{key.inspect} to be rejected"
        expect(entry.errors[:key]).to eq(['is invalid'])
      end
    end

    it 'finds an entry by its key given with surrounding whitespace' do
      entry = create_entry(key: 'KB-060')

      expect(agent_bot.knowledge_entries.find_by(key: " KB-060\n")).to eq(entry)
    end

    it 'is unique per bot' do
      create_entry(key: 'KB-001')

      expect(build(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001')).not_to be_valid
      expect(build(:agent_bot_knowledge_entry, key: 'KB-001')).to be_valid
    end

    it 'gives bulk callers the next number of the bot' do
      expect(described_class.next_key_number(agent_bot.id)).to eq(1)

      create_entry(key: 'KB-041')

      expect(described_class.next_key_number(agent_bot.id)).to eq(42)
    end

    it 'holds the key lock of a bot while the transaction lasts, without blocking other bots' do
      described_class.lock_keys!(agent_bot.id)
      other_session = ActiveRecord::Base.connection_pool.checkout
      try_lock = ->(bot_id) { other_session.select_value("SELECT pg_try_advisory_xact_lock(#{described_class::KEY_LOCK_NAMESPACE}, #{bot_id})") }

      expect(try_lock.call(agent_bot.id)).to be(false)
      expect(try_lock.call(agent_bot.id + 1)).to be(true)
    ensure
      ActiveRecord::Base.connection_pool.checkin(other_session) if other_session
    end
  end

  describe 'keys of entries created at the same time' do
    # Each thread needs its own connection, and both must see the bot, so nothing runs in a rolled back test
    # transaction here. The rows are inserted without callbacks and deleted after the example.
    self.use_transactional_tests = false

    let(:connection) { ActiveRecord::Base.connection }
    let!(:account_id) do
      connection.select_value("INSERT INTO accounts (name, created_at, updated_at) VALUES ('Key lock', now(), now()) RETURNING id")
    end
    let!(:agent_bot_id) do
      connection.select_value(
        "INSERT INTO agent_bots (name, account_id, bot_type, created_at, updated_at) VALUES ('Key lock', #{account_id}, 1, now(), now()) RETURNING id"
      )
    end

    # The entries go with the bot through the cascade; the sequences are the ones the accounts insert trigger creates
    after do
      connection.execute("DELETE FROM agent_bots WHERE id = #{agent_bot_id}")
      connection.execute("DELETE FROM accounts WHERE id = #{account_id}")
      connection.execute("DROP SEQUENCE IF EXISTS conv_dpid_seq_#{account_id}, camp_dpid_seq_#{account_id}")
    end

    def create_entry
      described_class.create!(agent_bot_id: agent_bot_id, question: 'Is this a sample question?', status: :needs_answer)
    end

    def wait_until_another_session_waits_for_the_key_lock
      sql = "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE locktype = 'advisory' AND NOT granted " \
            'AND database = (SELECT oid FROM pg_database WHERE datname = current_database()) ' \
            "AND classid = #{described_class::KEY_LOCK_NAMESPACE} AND objid = #{agent_bot_id})"
      deadline = 5.seconds.from_now
      sleep 0.05 until connection.select_value(sql) || Time.current > deadline
    end

    it 'numbers them one after the other' do
      first_created = Queue.new
      second = Thread.new do
        first_created.pop
        ActiveRecord::Base.connection_pool.with_connection { create_entry.key }
      end

      first_key = described_class.transaction do
        key = create_entry.key
        first_created << true
        wait_until_another_session_waits_for_the_key_lock
        key
      end

      expect([first_key, second.value]).to eq(%w[KB-001 KB-002])
    end
  end

  it 'deletes its customer questions with it' do
    question = create(:agent_bot_knowledge_question)

    question.knowledge_entry.destroy!

    expect(AgentBotKnowledgeQuestion.exists?(question.id)).to be(false)
  end
end
