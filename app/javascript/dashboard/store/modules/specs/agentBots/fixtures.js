export const agentBotRecords = [
  {
    account_id: 1,
    id: 11,
    name: 'Agent Bot 11',
    description: 'Agent Bot Description',
    bot_type: 'webhook',
    thumbnail: 'https://example.com/thumbnail.jpg',
    bot_config: {},
    outgoing_url: 'https://example.com/outgoing',
    access_token: 'hN8QwG769RqBXmme',
    system_bot: false,
  },

  {
    account_id: 1,
    id: 12,
    name: 'Agent Bot 12',
    description: 'Agent Bot Description 12',
    bot_type: 'webhook',
    thumbnail: 'https://example.com/thumbnail.jpg',
    bot_config: {},
    outgoing_url: 'https://example.com/outgoing',
    access_token: 'hN8QwG769RqBXmme',
    system_bot: false,
  },
];

export const agentBotData = {
  name: 'Test Bot',
  description: 'Test Description',
  outgoing_url: 'https://test.com',
  bot_type: 'webhook',
  avatar: new File([''], 'filename'),
};

export const aiAgentBotData = {
  name: 'Assistant',
  description: 'Answers visitors',
  outgoing_url: '',
  bot_type: 'ai_agent',
  bot_config: {
    model: 'gpt-test-mini',
    reasoning_effort: '',
    tone_of_voice: '',
    instructions: 'Keep replies short.',
    handoff_team_id: null,
    max_replies_per_conversation: 25,
    fallback_message: '',
  },
};
