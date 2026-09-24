require 'rails_helper'

RSpec.describe 'Integration Hooks API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:params) { { app_id: 'dialogflow', inbox_id: inbox.id, settings: { project_id: 'xx', credentials: { test: 'test' }, region: 'europe-west1' } } }

  describe 'POST /api/v1/accounts/{account.id}/integrations/hooks' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates hooks if admin' do
        post api_v1_account_integrations_hooks_url(account_id: account.id),
             params: params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['app_id']).to eq params[:app_id]
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}' do
    let(:hook) { create(:integrations_hook, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates hook if admin' do
        patch api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
              params: params,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['app_id']).to eq 'slack'
      end

      it 'preserves an existing OpenAI API key when updating editable settings' do
        allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
        openai_hook = create(:integrations_hook, :openai, account: account,
                                                          settings: { 'api_key' => 'sk-existing', 'translation_model' => 'gpt-old' })

        patch api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
              params: {
                settings: {
                  api_key: '',
                  translation_model: 'gpt-new',
                  prepare_answer_instructions: 'Custom prepare prompt'
                }
              },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(openai_hook.reload.settings['api_key']).to eq('sk-existing')
        expect(openai_hook.settings['translation_model']).to eq('gpt-new')
        expect(response.parsed_body['settings']).not_to have_key('api_key')
        expect(response.parsed_body['sensitive_settings_configured']['api_key_configured']).to be true
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}/openai_models' do
    let(:openai_hook) do
      allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'sk-existing' })
    end

    before do
      stub_request(:get, 'https://api.openai.com/v1/models')
        .with(headers: { 'Authorization' => 'Bearer sk-existing' })
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { data: [{ id: 'gpt-4.1-mini', created: 1 }, { id: 'gpt-6-luna', created: 2 }] }.to_json)
    end

    it 'returns unauthorized if agent' do
      get openai_models_api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the models available to the API key, newest first, if admin' do
      get openai_models_api_v1_account_integrations_hook_url(account_id: account.id, id: openai_hook.id),
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq(%w[gpt-6-luna gpt-4.1-mini])
    end

    it 'rejects hooks of other integrations' do
      hook = create(:integrations_hook, account: account)

      get openai_models_api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}/process_event' do
    let(:hook) { create(:integrations_hook, account: account) }
    let(:params) { { event: 'rephrase', payload: { test: 'test' } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post process_event_api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
             params: params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'will process the events' do
        post process_event_api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq 'No processor found'
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/integrations/hooks/{hook_id}' do
    let(:hook) { create(:integrations_hook, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'return unauthorized if agent' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates hook if admin' do
        delete api_v1_account_integrations_hook_url(account_id: account.id, id: hook.id),
               headers: admin.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Integrations::Hook.exists?(hook.id)).to be false
      end
    end
  end
end
