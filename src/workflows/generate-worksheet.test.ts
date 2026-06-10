import assert from 'assert';
import { buildTodayWorksheet, applyWorksheetAnswers } from './generate-worksheet';
import type { WorksheetSubmission, ReviewNote } from '../types/worksheets';

describe('generate-worksheet', () => {
  // -------------------------------------------------------------------------
  // buildTodayWorksheet
  // -------------------------------------------------------------------------

  it('buildTodayWorksheet always includes two free_capture fields', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-05-26T09:00:00'));
    const captureFields = ws.fields.filter((f) => f.kind === 'free_capture');
    assert.strictEqual(captureFields.length, 2, 'expected 2 free_capture fields');
    assert.deepStrictEqual(captureFields[0].binding, { action: 'new_note' });
    assert.deepStrictEqual(captureFields[1].binding, { action: 'new_note' });
    assert.strictEqual(ws.id, 'ws_2026-05-26');
    assert.ok(ws.title.includes('2026-05-26'), 'title should contain date');
  });

  it('buildTodayWorksheet appends note_review field when notes returned', async () => {
    const reviewNotes: ReviewNote[] = [
      { id: 1, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03' },
    ];
    const ws = await buildTodayWorksheet(new Date('2026-05-26T09:00:00'), {
      fetchReviewNotes: async () => reviewNotes,
    });
    const reviewField = ws.fields.find((f) => f.kind === 'note_review');
    assert.ok(reviewField, 'expected a note_review field');
    assert.deepStrictEqual(reviewField!.notes, reviewNotes);
    assert.deepStrictEqual(reviewField!.binding, { action: 'acknowledge' });
  });

  it('buildTodayWorksheet omits note_review field when no notes', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-05-26T09:00:00'), {
      fetchReviewNotes: async () => [],
    });
    assert.ok(
      ws.fields.every((f) => f.kind !== 'note_review'),
      'should not contain a note_review field'
    );
  });

  // -------------------------------------------------------------------------
  // applyWorksheetAnswers
  // -------------------------------------------------------------------------

  it('applyWorksheetAnswers creates notes for non-blank, skips blanks', async () => {
    const created: string[] = [];
    const deps = {
      createNote: async (text: string) => {
        created.push(text);
        return created.length;
      },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_2026-05-26',
      answers: [
        { fieldId: 'f1', chosenAction: 'new_note', text: 'Book conference travel' },
        { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.deepStrictEqual(created, ['Book conference travel']);
    assert.deepStrictEqual(result.results[0], { fieldId: 'f1', outcome: 'applied', noteId: 1 });
    assert.deepStrictEqual(result.results[1], { fieldId: 'f2', outcome: 'skipped', reason: 'empty' });
    assert.deepStrictEqual(result.relatedNotes, []);
  });

  it('applyWorksheetAnswers marks failed when createNote throws, continues batch', async () => {
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

    assert.strictEqual(result.results[0].outcome, 'failed');
    assert.deepStrictEqual(result.results[1], { fieldId: 'f2', outcome: 'applied', noteId: 42 });
  });

  it('applyWorksheetAnswers records acknowledged outcome', async () => {
    const deps = { createNote: async () => 1 };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f3', chosenAction: 'acknowledge', text: '' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.deepStrictEqual(result.results[0], { fieldId: 'f3', outcome: 'acknowledged' });
  });

  it('applyWorksheetAnswers calls findRelatedNotes for applied new_note answers', async () => {
    const related = [
      { noteId: 99, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03', score: 0.92 },
    ];
    const deps = {
      createNote: async () => 42,
      findRelatedNotes: async () => related,
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'dentist again' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.deepStrictEqual(result.relatedNotes, [{ fieldId: 'f1', matches: related }]);
  });

  it('applyWorksheetAnswers returns empty relatedNotes when findRelatedNotes throws', async () => {
    const deps = {
      createNote: async () => 42,
      findRelatedNotes: async () => {
        throw new Error('ollama down');
      },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'something' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.strictEqual(result.results[0].outcome, 'applied');
    assert.deepStrictEqual(result.relatedNotes, []);
  });
});
