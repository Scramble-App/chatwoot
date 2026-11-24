import { frontendURL } from '../../../helper/URLHelper';
import AiAgentIndexPage from './pages/AiAgentIndexPage.vue';
import KnowledgeBasePage from './pages/KnowledgeBasePage.vue';

// Agents can open the pages; the API decides who may manage which knowledge base
const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai-agent'),
    name: 'ai_agent_index',
    component: AiAgentIndexPage,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/ai-agent/:botId/knowledge'),
    name: 'ai_agent_knowledge',
    component: KnowledgeBasePage,
    meta,
  },
];
