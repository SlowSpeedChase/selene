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

export interface MapMeta {
  purpose?: string;
  reads?: string;
  writes?: string;
  trigger?: string;
}
/** Harvest `// @map <key>: <value>` lines from the top of a workflow file. */
export function parseMapComment(source: string): MapMeta {
  const meta: MapMeta = {};
  const re = /^\/\/\s*@map\s+(purpose|reads|writes|trigger):\s*(.+)$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) !== null) {
    meta[m[1] as keyof MapMeta] = m[2].trim();
  }
  return meta;
}

export interface WorkflowRow {
  name: string;
  schedule: string;
  purpose: string;
  reads: string;
  writes: string;
}
export function renderWorkflowTable(rows: WorkflowRow[]): string {
  const sorted = [...rows].sort((a, b) => a.name.localeCompare(b.name));
  const header = '| Workflow | Schedule | Reads | Writes | Purpose |\n|---|---|---|---|---|';
  const body = sorted
    .map((r) => `| [${r.name}](../src/workflows/${r.name}.ts) | ${r.schedule} | ${r.reads} | ${r.writes} | ${r.purpose} |`)
    .join('\n');
  return `${header}\n${body}`;
}

const MARK_START = '<!-- GENERATED:workflows START -->';
const MARK_END = '<!-- GENERATED:workflows END -->';
export function injectGenerated(doc: string, generated: string): string {
  const start = doc.indexOf(MARK_START);
  const end = doc.indexOf(MARK_END);
  if (start === -1 || end === -1 || end < start) {
    throw new Error('SYSTEM-MAP.md is missing the GENERATED:workflows markers');
  }
  const before = doc.slice(0, start + MARK_START.length);
  const after = doc.slice(end);
  return `${before}\n${generated}\n${after}`;
}

export function buildRow(name: string, meta: MapMeta, plistSchedule: string | null): WorkflowRow {
  return {
    name,
    schedule: plistSchedule ?? meta.trigger ?? '—',
    purpose: meta.purpose ?? '—',
    reads: meta.reads ?? '—',
    writes: meta.writes ?? '—',
  };
}
