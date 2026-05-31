import { describe, it, expect } from '@jest/globals';
import { parseSchedule } from './system-map';

describe('parseSchedule', () => {
  it('humanizes StartInterval seconds', () => {
    const plist = `<key>StartInterval</key>\n<integer>300</integer>`;
    expect(parseSchedule(plist)).toBe('every 5 min');
  });
  it('humanizes a 30-min interval', () => {
    expect(parseSchedule(`<key>StartInterval</key><integer>1800</integer>`)).toBe('every 30 min');
  });
  it('humanizes an hourly interval', () => {
    expect(parseSchedule(`<key>StartInterval</key><integer>3600</integer>`)).toBe('hourly');
  });
  it('renders StartCalendarInterval as a daily time', () => {
    const plist = `<key>StartCalendarInterval</key><dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>`;
    expect(parseSchedule(plist)).toBe('daily 06:00');
  });
  it('returns null when no schedule key is present', () => {
    expect(parseSchedule(`<key>RunAtLoad</key><true/>`)).toBeNull();
  });
});
