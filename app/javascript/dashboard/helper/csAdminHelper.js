// Contacts can set their own attributes through the widget, so only CS admin links are trusted
export const CS_ADMIN_ORIGIN = 'https://founder.scrambleup.com';

export const trustedCsAdminUrl = value => {
  try {
    const url = new URL(value);
    return url.origin === CS_ADMIN_ORIGIN ? url.href : '';
  } catch {
    return '';
  }
};
