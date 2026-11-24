/* global axios */
import ApiClient from './ApiClient';

class AgentBotsAPI extends ApiClient {
  constructor() {
    super('agent_bots', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteAgentBotAvatar(botId) {
    return axios.delete(`${this.url}/${botId}/avatar`);
  }

  resetAccessToken(botId) {
    return axios.post(`${this.url}/${botId}/reset_access_token`);
  }

  resetSecret(botId) {
    return axios.post(`${this.url}/${botId}/reset_secret`);
  }

  getAiAgentDefaults() {
    return axios.get(`${this.url}/ai_agent_defaults`);
  }

  getPages(botId) {
    return axios.get(`${this.url}/${botId}/pages`);
  }

  createPage(botId, url) {
    return axios.post(`${this.url}/${botId}/pages`, { url });
  }

  deletePage(botId, pageId) {
    return axios.delete(`${this.url}/${botId}/pages/${pageId}`);
  }

  refreshPage(botId, pageId) {
    return axios.post(`${this.url}/${botId}/pages/${pageId}/refresh`);
  }
}

export default new AgentBotsAPI();
