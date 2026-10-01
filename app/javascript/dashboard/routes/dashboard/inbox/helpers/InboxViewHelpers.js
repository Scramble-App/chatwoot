import wootConstants from 'dashboard/constants/globals';

// Snoozed and read notifications are shown until the agent changes the display options
export const DEFAULT_INBOX_FILTER = {
  status: wootConstants.INBOX_DISPLAY_BY.SNOOZED,
  type: wootConstants.INBOX_DISPLAY_BY.READ,
  sort_by: wootConstants.INBOX_SORT_BY.NEWEST,
};

export const savedInboxFilter = uiSettings =>
  uiSettings?.inbox_filter_by || DEFAULT_INBOX_FILTER;

export const NOTIFICATION_TYPES_MAPPING = {
  CONVERSATION_MENTION: ['i-lucide-at-sign', 'text-n-blue-11'],
  CONVERSATION_ASSIGNMENT: ['i-lucide-chevrons-right', 'text-n-blue-11'],
  CONVERSATION_CREATION: ['i-lucide-mail-plus', 'text-n-blue-11'],
  PARTICIPATING_CONVERSATION_NEW_MESSAGE: [
    'i-lucide-message-square-plus',
    'text-n-blue-11',
  ],
  ASSIGNED_CONVERSATION_NEW_MESSAGE: [
    'i-lucide-message-square-plus',
    'text-n-blue-11',
  ],
  SLA_MISSED_FIRST_RESPONSE: ['i-lucide-heart-crack', 'text-n-ruby-11'],
  SLA_MISSED_NEXT_RESPONSE: ['i-lucide-heart-crack', 'text-n-ruby-11'],
  SLA_MISSED_RESOLUTION: ['i-lucide-heart-crack', 'text-n-ruby-11'],
};
