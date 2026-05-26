import { describe, it, expect } from 'vitest';
import { buildTodayWorksheet, applyWorksheetAnswers } from './generate-worksheet';
import type { WorksheetSubmission } from '../types/worksheets';

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

describe('applyWorksheetAnswers', () => {
  it('creates a note for each non-blank new_note answer and skips blanks', async () => {
    const created: string[] = [];
    const deps = {
      createNote: async (text: string) => { created.push(text); return created.length; },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_2026-05-26',
      answers: [
        { fieldId: 'f1', chosenAction: 'new_note', text: 'Book conference travel' },
        { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(created).toEqual(['Book conference travel']);
    expect(result.results).toEqual([
      { fieldId: 'f1', outcome: 'applied', noteId: 1 },
      { fieldId: 'f2', outcome: 'skipped', reason: 'empty' },
    ]);
  });

  it('marks a field failed when createNote throws, without aborting the batch', async () => {
    const deps = {
      createNote: async (text: string) => {
        if (text === 'boom') throw new Error('db error');
        return 42;
      },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [
        { fieldId: 'f1', chosenAction: 'new_note', text: 'boom' },
        { fieldId: 'f2', chosenAction: 'new_note', text: 'ok' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0].outcome).toBe('failed');
    expect(result.results[1]).toEqual({ fieldId: 'f2', outcome: 'applied', noteId: 42 });
  });
});
