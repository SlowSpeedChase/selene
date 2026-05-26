import { describe, it, expect } from 'vitest';
import { buildTodayWorksheet } from './generate-worksheet';

describe('buildTodayWorksheet', () => {
  it('builds a worksheet with a single free_capture field for the given date', () => {
    const ws = buildTodayWorksheet(new Date('2026-05-26T09:00:00'));
    expect(ws.id).toBe('ws_2026-05-26');
    expect(ws.fields).toHaveLength(1);
    expect(ws.fields[0].kind).toBe('free_capture');
    expect(ws.fields[0].binding).toEqual({ action: 'new_note' });
    expect(ws.fields[0].id).toBeTruthy();
    expect(ws.title).toContain('2026-05-26');
  });
});
