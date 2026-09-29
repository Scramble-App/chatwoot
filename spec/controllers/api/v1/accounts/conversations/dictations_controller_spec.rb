require 'rails_helper'

RSpec.describe 'Conversation Dictation API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/dictation" }
  let(:transcriptions_url) { 'https://api.openai.com/v1/audio/transcriptions' }
  let(:audio) { fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg') }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'openai-key', 'dictation_terms' => 'Scramble, KYC' })
  end

  it 'returns the transcript of the recording without creating a message' do
    agent.account_users.find_by!(account: account).update!(translation_locale: 'pt_BR')
    transcription = stub_request(:post, transcriptions_url)
                    .with do |request|
                      request.headers['Authorization'] == 'Bearer openai-key' &&
                        request.body.include?("name=\"model\"\r\n\r\ngpt-transcribe\r\n") &&
                        request.body.include?("name=\"language\"\r\n\r\npt\r\n") &&
                        request.body.include?("name=\"prompt\"\r\n\r\nScramble, KYC\r\n") &&
                        request.body.include?('filename="sample.mp3"')
                    end
                    .to_return(status: 200, body: { text: " Hello, your transfer has arrived.\n" }.to_json)

    expect do
      post url, params: { audio: audio }, headers: agent.create_new_auth_token
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('text' => 'Hello, your transfer has arrived.')
    expect(transcription).to have_been_requested
  end

  it 'uses the configured model and leaves out the hints nobody set' do
    Integrations::Hook.find_by!(account: account, app_id: 'openai').update!(settings: { 'api_key' => 'openai-key', 'dictation_model' => 'whisper-1' })
    transcription = stub_request(:post, transcriptions_url)
                    .with do |request|
                      request.body.include?("name=\"model\"\r\n\r\nwhisper-1\r\n") &&
                        request.body.exclude?('name="language"') && request.body.exclude?('name="prompt"')
                    end
                    .to_return(status: 200, body: { text: 'Hello' }.to_json)

    post url, params: { audio: audio }, headers: agent.create_new_auth_token

    expect(response.parsed_body).to eq('text' => 'Hello')
    expect(transcription).to have_been_requested
  end

  it 'returns unauthorized for an agent outside the inbox and does not call OpenAI' do
    outsider = create(:user, account: account, role: :agent)

    post url, params: { audio: audio }, headers: outsider.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:post, transcriptions_url)).not_to have_been_made
  end

  it 'explains when the OpenAI integration is not configured' do
    Integrations::Hook.where(account: account, app_id: 'openai').destroy_all

    post url, params: { audio: audio }, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('OpenAI integration is not configured')
    expect(a_request(:post, transcriptions_url)).not_to have_been_made
  end

  it 'passes the OpenAI error on to the agent' do
    stub_request(:post, transcriptions_url).to_return(status: 400, body: { error: { message: 'Audio file might be corrupted' } }.to_json)

    post url, params: { audio: audio }, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('Audio file might be corrupted')
  end

  it 'rejects a recording above the OpenAI size limit before uploading it' do
    stub_const('Dictations::OpenaiTranscriptionService::MAX_AUDIO_SIZE', 1.kilobyte)

    post url, params: { audio: audio }, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a_request(:post, transcriptions_url)).not_to have_been_made
  end

  it 'rejects a request without a recording' do
    post url, params: { audio: 'not a file' }, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('Audio recording is required')
    expect(a_request(:post, transcriptions_url)).not_to have_been_made
  end
end
