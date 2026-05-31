/** Parse a launchd plist's schedule into a human label, or null if none. */
export function parseSchedule(plistXml: string): string | null {
  const interval = plistXml.match(/<key>StartInterval<\/key>\s*<integer>(\d+)<\/integer>/);
  if (interval) {
    const secs = parseInt(interval[1], 10);
    if (secs % 3600 === 0) {
      const h = secs / 3600;
      return h === 1 ? 'hourly' : `every ${h} hr`;
    }
    return `every ${Math.round(secs / 60)} min`;
  }
  const cal = plistXml.match(/<key>StartCalendarInterval<\/key>\s*<dict>([\s\S]*?)<\/dict>/);
  if (cal) {
    const hour = cal[1].match(/<key>Hour<\/key>\s*<integer>(\d+)<\/integer>/);
    const min = cal[1].match(/<key>Minute<\/key>\s*<integer>(\d+)<\/integer>/);
    const hh = (hour ? hour[1] : '0').padStart(2, '0');
    const mm = (min ? min[1] : '0').padStart(2, '0');
    return `daily ${hh}:${mm}`;
  }
  return null;
}
