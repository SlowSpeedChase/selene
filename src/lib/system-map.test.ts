import { describe, it, expect } from '@jest/globals';
import { parseSchedule, parseMapComment, renderWorkflowTable, WorkflowRow } from './system-map';

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

describe('parseMapComment', () => {
  it('extracts purpose, reads, writes, trigger', () => {
    const src = [
      '// @map purpose: Extract concepts, themes, energy',
      '// @map reads: raw_notes',
      '// @map writes: processed_notes',
      '// @map trigger: webhook',
      'import { foo } from "bar";',
    ].join('\n');
    expect(parseMapComment(src)).toEqual({
      purpose: 'Extract concepts, themes, energy',
      reads: 'raw_notes', writes: 'processed_notes', trigger: 'webhook',
    });
  });
  it('returns empty fields when no @map comment present', () => {
    expect(parseMapComment('import x from "y";')).toEqual({});
  });
});

describe('renderWorkflowTable', () => {
  it('renders a sorted markdown table with links', () => {
    const rows: WorkflowRow[] = [
      { name: 'process-llm', schedule: 'every 5 min', purpose: 'Extract concepts', reads: 'raw_notes', writes: 'processed_notes' },
      { name: 'ingest', schedule: 'webhook', purpose: 'Capture notes', reads: '—', writes: 'raw_notes' },
    ];
    const md = renderWorkflowTable(rows);
    expect(md.indexOf('ingest')).toBeLessThan(md.indexOf('process-llm'));
    expect(md).toContain('[ingest](../src/workflows/ingest.ts)');
    expect(md).toContain('| Workflow | Schedule | Reads | Writes | Purpose |');
  });
});
