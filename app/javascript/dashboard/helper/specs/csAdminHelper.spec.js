import { trustedCsAdminUrl } from '../csAdminHelper';

describe('#trustedCsAdminUrl', () => {
  it('returns a CS admin link as is', () => {
    const url = 'https://founder.scrambleup.com/cs-dashboard/users/20619/';
    expect(trustedCsAdminUrl(url)).toBe(url);
  });

  it.each([
    // A script URL is exactly what a contact could plant, so the test needs one
    // eslint-disable-next-line no-script-url
    ['a script URL', 'javascript:alert(document.cookie)'],
    [
      'a lookalike host',
      'https://founder.scrambleup.com.evil.example/cs-dashboard/users/1/',
    ],
    ['another host', 'https://evil.example/cs-dashboard/users/1/'],
    ['plain http', 'http://founder.scrambleup.com/cs-dashboard/users/1/'],
    ['an invalid value', 'not a url'],
    ['a missing value', undefined],
  ])('rejects %s', (_label, value) => {
    expect(trustedCsAdminUrl(value)).toBe('');
  });
});
