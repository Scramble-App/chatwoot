import {
  formatDate,
  formatUnixDate,
  isTimeAfter,
  generateRelativeTime,
  getUnixStartOfDay,
  getUnixEndOfDay,
  fromUnixTimeInZone,
} from '../DateHelper';

describe('#DateHelper', () => {
  it('should format unix date correctly without dateFormat', () => {
    expect(formatUnixDate(1576340626)).toEqual('Dec 14, 2019');
  });

  it('should format unix date correctly without dateFormat', () => {
    expect(formatUnixDate(1608214031, 'MM/dd/yyyy')).toEqual('12/17/2020');
  });

  it('should format date', () => {
    expect(
      formatDate({
        date: 'Dec 14, 2019',
        todayText: 'Today',
        yesterdayText: 'Yesterday',
      })
    ).toEqual('Dec 14, 2019');
  });
  it('should format date as today ', () => {
    expect(
      formatDate({
        date: new Date(),
        todayText: 'Today',
        yesterdayText: 'Yesterday',
      })
    ).toEqual('Today');
  });
  it('should format date as yesterday ', () => {
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    expect(
      formatDate({
        date: yesterday,
        todayText: 'Today',
        yesterdayText: 'Yesterday',
      })
    ).toEqual('Yesterday');
  });
});

// Specs run with TZ=UTC as the browser timezone; Tallinn is UTC+3 in October 2026
describe('#getUnixStartOfDay and #getUnixEndOfDay', () => {
  const pickedDay = new Date(2026, 9, 1, 15, 30);

  it('uses the browser timezone without a timezone', () => {
    expect(getUnixStartOfDay(pickedDay)).toEqual(Date.UTC(2026, 9, 1) / 1000);
    expect(getUnixEndOfDay(pickedDay)).toEqual(
      Date.UTC(2026, 9, 1, 23, 59, 59) / 1000
    );
  });

  it('takes the picked calendar day in the given timezone', () => {
    expect(getUnixStartOfDay(pickedDay, 'Europe/Tallinn')).toEqual(
      Date.UTC(2026, 8, 30, 21) / 1000
    );
    expect(getUnixEndOfDay(pickedDay, 'Europe/Tallinn')).toEqual(
      Date.UTC(2026, 9, 1, 20, 59, 59) / 1000
    );
  });
});

describe('#fromUnixTimeInZone', () => {
  // 30 September 2026, 22:30 UTC is 1 October, 01:30 in Tallinn
  const timestamp = Date.UTC(2026, 8, 30, 22, 30) / 1000;

  it('returns the wall-clock time of the given timezone', () => {
    const date = fromUnixTimeInZone(timestamp, 'Europe/Tallinn');

    expect([date.getDate(), date.getHours(), date.getMinutes()]).toEqual([
      1, 1, 30,
    ]);
  });

  it('uses the browser timezone without a timezone', () => {
    const date = fromUnixTimeInZone(timestamp, null);

    expect([date.getDate(), date.getHours()]).toEqual([30, 22]);
  });
});

describe('#isTimeAfter', () => {
  it('return correct values', () => {
    expect(isTimeAfter(5, 30, 9, 30)).toEqual(false);
    expect(isTimeAfter(9, 30, 9, 30)).toEqual(true);
    expect(isTimeAfter(9, 29, 9, 30)).toEqual(false);
    expect(isTimeAfter(11, 59, 12, 0)).toEqual(false);
  });
});

describe('generateRelativeTime', () => {
  it('should return a string with the relative time', () => {
    const value = 1;
    const unit = 'second';
    const languageCode = 'en-US';
    const expectedResult = 'in 1 second';

    const actualResult = generateRelativeTime(value, unit, languageCode);

    expect(actualResult).toBe(expectedResult);
  });

  it('should return a string with the relative time in a different language', () => {
    const value = 10;
    const unit = 'minute';
    const languageCode = 'de-DE';
    const expectedResult = 'in 10 Minuten';

    const actualResult = generateRelativeTime(value, unit, languageCode);

    expect(actualResult).toBe(expectedResult);
  });

  it('should return a string with the relative time for a different unit', () => {
    const value = 1;
    const unit = 'hour';
    const languageCode = 'en-US';
    const expectedResult = 'in 1 hour';

    const actualResult = generateRelativeTime(value, unit, languageCode);

    expect(actualResult).toBe(expectedResult);
  });

  it('should throw an error if the value is not a number', () => {
    const value = 1;
    const unit = 'day';
    const languageCode = 'en_US';
    const expectedResult = 'tomorrow';

    const actualResult = generateRelativeTime(value, unit, languageCode);

    expect(actualResult).toBe(expectedResult);
  });

  it('should throw an error if the value is not a number', () => {
    const value = 1;
    const unit = 'day';
    const languageCode = 'en-US';
    const expectedResult = 'tomorrow';

    const actualResult = generateRelativeTime(value, unit, languageCode);

    expect(actualResult).toBe(expectedResult);
  });
});
