import { DEFAULT_INBOX_FILTER, savedInboxFilter } from '../InboxViewHelpers';

describe('savedInboxFilter', () => {
  it('shows snoozed and read notifications when the agent has not chosen yet', () => {
    expect(savedInboxFilter({})).toEqual({
      status: 'snoozed',
      type: 'read',
      sort_by: 'desc',
    });
    expect(savedInboxFilter(undefined)).toBe(DEFAULT_INBOX_FILTER);
  });

  it("keeps the agent's saved display options", () => {
    const inboxFilterBy = { status: '', type: 'read', sort_by: 'asc' };

    expect(savedInboxFilter({ inbox_filter_by: inboxFilterBy })).toBe(
      inboxFilterBy
    );
  });
});
