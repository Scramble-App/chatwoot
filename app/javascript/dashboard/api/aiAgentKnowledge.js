/* global axios */
import ApiClient from './ApiClient';

const ENTRY_FILTERS = ['q', 'category', 'status', 'sort', 'page'];

// Blank filters are left out so the index uses its defaults
export const buildEntriesParams = (filters = {}) =>
  Object.fromEntries(
    ENTRY_FILTERS.filter(
      key => filters[key] !== undefined && filters[key] !== ''
    ).map(key => [key, filters[key]])
  );

class AiAgentKnowledgeAPI extends ApiClient {
  constructor() {
    super('agent_bots', { accountScoped: true });
  }

  entriesUrl(botId) {
    return `${this.url}/${botId}/knowledge_entries`;
  }

  getKnowledgeBases() {
    return axios.get(`${this.url}/knowledge_bases`);
  }

  getEntries(botId, filters) {
    return axios.get(this.entriesUrl(botId), {
      params: buildEntriesParams(filters),
    });
  }

  showEntry(botId, id) {
    return axios.get(`${this.entriesUrl(botId)}/${id}`);
  }

  createEntry(botId, entry) {
    return axios.post(this.entriesUrl(botId), entry);
  }

  updateEntry(botId, id, entry) {
    return axios.patch(`${this.entriesUrl(botId)}/${id}`, entry);
  }

  deleteEntry(botId, id) {
    return axios.delete(`${this.entriesUrl(botId)}/${id}`);
  }

  importEntries(botId, { file, dryRun }) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('dry_run', String(dryRun));
    return axios.post(`${this.entriesUrl(botId)}/import`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // A blob keeps the UTF-8 BOM the server adds for Excel
  exportEntries(botId) {
    return axios.get(`${this.entriesUrl(botId)}/export`, {
      responseType: 'blob',
    });
  }
}

export default new AiAgentKnowledgeAPI();
