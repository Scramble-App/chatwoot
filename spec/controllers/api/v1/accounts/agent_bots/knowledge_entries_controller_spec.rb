require 'rails_helper'

RSpec.describe 'Agent bot knowledge entries API', type: :request do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:agent_bot) { create(:agent_bot, :ai_agent, account: account, bot_config: { handoff_team_id: team.id }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:team_agent) { create(:user, account: account, role: :agent).tap { |user| create(:team_member, team: team, user: user) } }
  let(:entries_url) { "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/knowledge_entries" }

  def csv_file(content)
    Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: 'knowledge.csv')
  end

  describe 'access' do
    let!(:entry) { create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001') }

    def request_every_endpoint(url, headers)
      [
        -> { get url, headers: headers, as: :json },
        -> { get "#{url}/#{entry.id}", headers: headers, as: :json },
        -> { post url, headers: headers, params: { question: 'New?', status: 'draft' }, as: :json },
        -> { patch "#{url}/#{entry.id}", headers: headers, params: { question: 'Changed?' }, as: :json },
        -> { delete "#{url}/#{entry.id}", headers: headers, as: :json },
        -> { post "#{url}/import", headers: headers, params: { file: csv_file("Вопрос\nImported?\n") } },
        -> { get "#{url}/export", headers: headers }
      ].map do |request|
        request.call
        response.status
      end
    end

    it 'rejects an unauthenticated user' do
      expect(request_every_endpoint(entries_url, {})).to all(eq(401))
    end

    it 'rejects an agent outside the handoff team and changes nothing' do
      other_team_agent = create(:user, account: account, role: :agent)
      create(:team_member, team: create(:team, account: account), user: other_team_agent)

      expect(request_every_endpoint(entries_url, other_team_agent.create_new_auth_token)).to all(eq(401))
      expect(agent_bot.knowledge_entries.pluck(:key, :question)).to eq([['KB-001', entry.question]])
    end

    it 'rejects every agent when the bot has no handoff team' do
      agent_bot.update!(bot_config: {})

      expect(request_every_endpoint(entries_url, team_agent.create_new_auth_token)).to all(eq(401))
      expect(agent_bot.knowledge_entries.count).to eq(1)
    end

    it 'rejects a user of another account' do
      outsider = create(:user, account: create(:account), role: :administrator)

      expect(request_every_endpoint(entries_url, outsider.create_new_auth_token)).to all(eq(401))
    end

    it 'does not find a bot of another account' do
      other_bot = create(:agent_bot, :ai_agent)
      create(:agent_bot_knowledge_entry, agent_bot: other_bot)
      url = "/api/v1/accounts/#{account.id}/agent_bots/#{other_bot.id}/knowledge_entries"

      expect(request_every_endpoint(url, admin.create_new_auth_token)).to all(eq(404))
      expect(other_bot.knowledge_entries.count).to eq(1)
    end

    it 'does not find a webhook bot' do
      webhook_bot = create(:agent_bot, account: account)
      url = "/api/v1/accounts/#{account.id}/agent_bots/#{webhook_bot.id}/knowledge_entries"

      expect(request_every_endpoint(url, admin.create_new_auth_token)).to all(eq(404))
    end

    it 'does not find an entry of another bot' do
      other_entry = create(:agent_bot_knowledge_entry, agent_bot: create(:agent_bot, :ai_agent, account: account))

      get "#{entries_url}/#{other_entry.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'lets an agent of the handoff team manage the knowledge base' do
      headers = team_agent.create_new_auth_token

      get entries_url, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      patch "#{entries_url}/#{entry.id}", headers: headers, params: { question: 'Changed?' }, as: :json
      expect(response).to have_http_status(:success)
      expect(entry.reload.question).to eq('Changed?')
    end
  end

  describe 'GET /knowledge_entries' do
    let(:headers) { admin.create_new_auth_token }

    before do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-002', category: 'Pricing', question: 'What are the fees?',
                                         short_answer: 'No fees for founders.', asked_count: 0)
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', category: 'Eligibility', question: 'Who can apply?',
                                         status: :draft, answer: nil, short_answer: nil)
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-003', category: 'Pricing', question: 'Is there a 100% refund?',
                                         status: :needs_answer, answer: nil, short_answer: nil, asked_count: 4,
                                         last_asked_at: Time.zone.at(1_700_000_000))
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-004', category: '', question: 'How long is the review?',
                                         status: :needs_answer, answer: nil, short_answer: nil, asked_count: 9)
      create(:agent_bot_knowledge_entry, key: 'KB-001', category: 'Other bot', question: 'What are the fees?')
    end

    it 'lists the entries of the bot by key with the meta of the knowledge base' do
      get entries_url, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['payload'].pluck('key')).to eq(%w[KB-001 KB-002 KB-003 KB-004])
      expect(body['meta']).to eq(
        'count' => 4, 'current_page' => 1, 'per_page' => 50, 'categories' => %w[Eligibility Pricing],
        'status_counts' => { 'draft' => 1, 'published' => 1, 'needs_answer' => 2 }
      )
      expect(body['payload'].third).to include(
        'key' => 'KB-003', 'category' => 'Pricing', 'question' => 'Is there a 100% refund?', 'status' => 'needs_answer',
        'asked_count' => 4, 'last_asked_at' => 1_700_000_000, 'answer' => nil, 'short_answer' => nil
      )
      expect(body['payload'].third['updated_at']).to be_a(Integer)
      expect(body['payload'].first.keys).to match_array(
        %w[id key category frequency question alternative_questions short_answer answer selling_point status asked_count last_asked_at updated_at]
      )
    end

    it 'filters by status, and counts the statuses of the other filters only' do
      get entries_url, headers: headers, params: { status: 'needs_answer', sort: 'asked_count' }

      body = response.parsed_body
      expect(body['payload'].pluck('key')).to eq(%w[KB-004 KB-003])
      expect(body['meta']['count']).to eq(2)
      expect(body['meta']['status_counts']).to eq('draft' => 1, 'published' => 1, 'needs_answer' => 2)
    end

    it 'filters by category and searches the key, question and answers' do
      get entries_url, headers: headers, params: { category: 'Pricing', q: 'fees' }

      body = response.parsed_body
      expect(body['payload'].pluck('key')).to eq(%w[KB-002])
      expect(body['meta']['status_counts']).to eq('draft' => 0, 'published' => 1, 'needs_answer' => 0)

      get entries_url, headers: headers, params: { q: 'kb-001' }
      expect(response.parsed_body['payload'].pluck('key')).to eq(%w[KB-001])

      get entries_url, headers: headers, params: { q: 'no FEES' }
      expect(response.parsed_body['payload'].pluck('key')).to eq(%w[KB-002])
    end

    it 'treats % and _ in the search as plain characters' do
      get entries_url, headers: headers, params: { q: '100%' }
      expect(response.parsed_body['payload'].pluck('key')).to eq(%w[KB-003])

      get entries_url, headers: headers, params: { q: '_' }
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'sorts by the latest update' do
      agent_bot.knowledge_entries.find_by(key: 'KB-002').update!(question: 'What are the fees now?')

      get entries_url, headers: headers, params: { sort: 'updated_at' }

      expect(response.parsed_body['payload'].first['key']).to eq('KB-002')
    end

    it 'returns 50 entries per page' do
      create_list(:agent_bot_knowledge_entry, 47, agent_bot: agent_bot)

      get entries_url, headers: headers, params: { page: 2 }

      body = response.parsed_body
      expect(body['payload'].size).to eq(1)
      expect(body['meta']).to include('count' => 51, 'current_page' => 2, 'per_page' => 50)
    end
  end

  describe 'GET /knowledge_entries/:id' do
    it 'returns the entry with its latest 20 customer questions and their conversation numbers' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer, answer: nil, short_answer: nil)
      conversation = create(:conversation, account: account)
      questions = Array.new(21) do |index|
        create(:agent_bot_knowledge_question, knowledge_entry: entry, conversation: conversation, content: "Wording #{index}",
                                              created_at: index.minutes.ago)
      end

      get "#{entries_url}/#{entry.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['key']).to eq(entry.key)
      expect(body['questions'].size).to eq(20)
      expect(body['questions'].first).to eq(
        'id' => questions.first.id, 'content' => 'Wording 0', 'conversation_id' => conversation.display_id,
        'created_at' => questions.first.created_at.to_i
      )
      expect(body['questions'].pluck('content')).not_to include('Wording 20')
    end
  end

  describe 'POST /knowledge_entries' do
    let(:headers) { admin.create_new_auth_token }

    it 'creates an entry with the next key and stores blank fields as nil' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-007')

      post entries_url, headers: headers, as: :json,
                        params: { key: '', category: 'Pricing', frequency: '', question: 'Are there fees?', alternative_questions: '',
                                  short_answer: 'No.', answer: '', selling_point: '', status: 'published' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('key' => 'KB-008', 'category' => 'Pricing', 'status' => 'published')
      entry = agent_bot.knowledge_entries.find_by(key: 'KB-008')
      expect(entry.attributes.slice('frequency', 'answer', 'selling_point', 'alternative_questions').values).to all(be_nil)
      expect(entry.account).to eq(account)
    end

    it 'returns the validation errors of the entry' do
      post entries_url, headers: headers, params: { question: 'Are there fees?', short_answer: '', answer: '', status: 'published' },
                        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('message' => 'Answer or short answer is required to publish the entry', 'attributes' => ['answer'])
    end

    it 'rejects an unknown or blank status' do
      ['archived', ''].each do |status|
        expect do
          post entries_url, headers: headers, params: { question: 'Are there fees?', status: status }, as: :json
        end.not_to change(AgentBotKnowledgeEntry, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('message' => 'Status is not included in the list', 'attributes' => ['status'])
      end
    end

    it 'rejects a key the bot already has' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001')

      post entries_url, headers: headers, params: { key: 'KB-001', question: 'Are there fees?', status: 'draft' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Key has already been taken')
    end
  end

  describe 'PATCH /knowledge_entries/:id' do
    it 'updates the entry' do
      entry = create(:agent_bot_knowledge_entry, agent_bot: agent_bot, status: :needs_answer, answer: nil, short_answer: nil)

      patch "#{entries_url}/#{entry.id}", headers: admin.create_new_auth_token, as: :json,
                                          params: { answer: 'Yes, from the UK too.', status: 'published', category: '' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => entry.id, 'answer' => 'Yes, from the UK too.', 'status' => 'published')
      expect(entry.reload).to have_attributes(status: 'published', category: nil)
    end
  end

  describe 'DELETE /knowledge_entries/:id' do
    it 'deletes the entry and its customer questions' do
      question = create(:agent_bot_knowledge_question, knowledge_entry: create(:agent_bot_knowledge_entry, agent_bot: agent_bot))

      delete "#{entries_url}/#{question.knowledge_entry_id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(AgentBotKnowledgeEntry.exists?(question.knowledge_entry_id)).to be(false)
      expect(AgentBotKnowledgeQuestion.exists?(question.id)).to be(false)
    end
  end

  describe 'POST /knowledge_entries/import' do
    let(:headers) { admin.create_new_auth_token }
    let(:valid_csv) { "\uFEFFID,Вопрос,Короткий ответ\nKB-001,Changed question?,Changed answer.\n,New question?,\n" }

    before { create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'Old question?') }

    it 'checks the file on a dry run without saving it' do
      post "#{entries_url}/import", headers: headers, params: { file: csv_file(valid_csv), dry_run: 'true' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('created' => 1, 'updated' => 1, 'errors' => [])
      expect(agent_bot.knowledge_entries.pluck(:question)).to eq(['Old question?'])
    end

    it 'imports the file' do
      post "#{entries_url}/import", headers: headers, params: { file: csv_file(valid_csv), dry_run: 'false' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('created' => 1, 'updated' => 1, 'errors' => [])
      expect(agent_bot.knowledge_entries.order(:key).pluck(:key, :question, :status)).to eq(
        [['KB-001', 'Changed question?', 'published'], ['KB-002', 'New question?', 'needs_answer']]
      )
    end

    it 'saves nothing and returns the row errors when a row is invalid' do
      csv = "ID,Вопрос,Статус\nKB-001,Changed question?,\n,,draft\n"

      post "#{entries_url}/import", headers: headers, params: { file: csv_file(csv) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('errors' => [{ 'row' => 3, 'message' => "Question can't be blank" }])
      expect(agent_bot.knowledge_entries.pluck(:question)).to eq(['Old question?'])
    end

    it 'returns the row errors of a dry run with a success status' do
      post "#{entries_url}/import", headers: headers, params: { file: csv_file("ID,Вопрос,Статус\n,,draft\n,New?,\n"), dry_run: 'true' }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('created' => 1, 'updated' => 0, 'errors' => [{ 'row' => 2, 'message' => "Question can't be blank" }])
    end

    it 'rejects a request without a file' do
      post "#{entries_url}/import", headers: headers, params: { dry_run: 'true' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'Choose a CSV file to import')
    end
  end

  describe 'GET /knowledge_entries/export' do
    it 'downloads the knowledge base as a CSV file with a BOM' do
      create(:agent_bot_knowledge_entry, agent_bot: agent_bot, key: 'KB-001', question: 'Are there fees?', short_answer: 'No.', answer: nil)

      get "#{entries_url}/export", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to eq('text/csv; charset=utf-8')
      expect(response.headers['Content-Disposition']).to include("attachment; filename=\"knowledge-base-#{agent_bot.id}.csv\"")
      body = response.body.dup.force_encoding(Encoding::UTF_8)
      expect(body).to start_with("\uFEFFID,Категория,Частота,Вопрос,")
      expect(CSV.parse(body.delete_prefix("\uFEFF"))[1]).to eq(['KB-001', nil, nil, 'Are there fees?', nil, 'No.', nil, nil, 'published'])
    end
  end
end
