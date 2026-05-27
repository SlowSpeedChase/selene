import { describe, it, expect } from 'vitest';
import { buildTodayWorksheet, applyWorksheetAnswers } from './generate-worksheet';
import type { WorksheetSubmission, ReviewNote } from '../types/worksheets';

// ---------------------------------------------------------------------------
// buildTodayWorksheet
// ---------------------------------------------------------------------------

describe('buildTodayWorksheet', () => {
  it('always includes two free_capture fields', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-05-26T09:00:00'));
    const captureFields = ws.fields.filter(f => f.kind === 'free_capture');
    expect(captureFields).toHaveLength(2);
    expect(captureFields[0].binding).toEqual({ action: 'new_note' });
    expect(captureFields[1].binding).toEqual({ action: 'new_note' });
    expect(ws.id).toBe('ws_2026-05-26');
    expect(ws.title).toContain('2026-05-26');
  });

  it('appends a note_review field when fetchReviewNotes returns notes', async () => {
    const reviewNotes: ReviewNote[] = [
      { id: 1, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03' },
    ];
    const ws = await buildTodayWorksheet(
      new Date('2026-05-26T09:00:00'),
      { fetchReviewNotes: async () => reviewNotes },
    );
    const reviewField = ws.fields.find(f => f.kind === 'note_review');
    expect(reviewField).toBeDefined();
    expect(reviewField!.notes).toEqual(reviewNotes);
    expect(reviewField!.binding).toEqual({ action: 'acknowledge' });
  });

  it('omits note_review field when fetchReviewNotes returns empty', async () => {
    const ws = await buildTodayWorksheet(
      new Date('2026-05-26T09:00:00'),
      { fetchReviewNotes: async () => [] },
    );
    expect(ws.fields.every(f => f.kind !== 'note_review')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// applyWorksheetAnswers
// ---------------------------------------------------------------------------

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
    expect(result.results[0]).toEqual({ fieldId: 'f1', outcome: 'applied', noteId: 1 });
    expect(result.results[1]).toEqual({ fieldId: 'f2', outcome: 'skipped', reason: 'empty' });
    expect(result.relatedNotes).toEqual([]);
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

  it('records acknowledged outcome for acknowledge answers', async () => {
    const deps = { createNote: async () => 1 };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f3', chosenAction: 'acknowledge', text: '' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0]).toEqual({ fieldId: 'f3', outcome: 'acknowledged' });
  });

  it('calls findRelatedNotes for each applied new_note answer', async () => {
    const related = [{ noteId: 99, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03', score: 0.92 }];
    const deps = {
      createNote: async () => 42,
      findRelatedNotes: async () => related,
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'dentist again' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.relatedNotes).toEqual([
      { fieldId: 'f1', matches: related },
    ]);
  });

  it('returns empty relatedNotes when findRelatedNotes throws', async () => {
    const deps = {
      createNote: async () => 42,
      findRelatedNotes: async () => { throw new Error('ollama down'); },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'something' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0].outcome).toBe('applied');
    expect(result.relatedNotes).toEqual([]);
  });
});
