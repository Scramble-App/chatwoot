export const NEEDS_ANSWER = 'needs_answer';

export const ENTRY_STATUSES = ['published', 'draft', NEEDS_ANSWER];

// The API answers these when the user may not manage the bot's knowledge base
// or the bot is not an AI agent of this account
export const NO_ACCESS_STATUSES = [401, 403, 404];
