import type {
  Worksheet,
  WorksheetSubmission,
  SubmissionResult,
  AnswerResult,
} from '../types/worksheets';

export function buildTodayWorksheet(now: Date = new Date()): Worksheet {
  const date = now.toISOString().slice(0, 10);
  return {
    id: `ws_${date}`,
    title: `Daily Review — ${date}`,
    fields: [
      {
        id: 'f1',
        kind: 'free_capture',
        prompt: "Anything on your mind? Write it and it'll become a note.",
        binding: { action: 'new_note' },
      },
    ],
  };
}

export interface ApplyDeps {
  createNote: (text: string) => Promise<number>;
}

export async function applyWorksheetAnswers(
  submission: WorksheetSubmission,
  deps: ApplyDeps,
): Promise<SubmissionResult> {
  const results: AnswerResult[] = [];
  for (const answer of submission.answers) {
    if (answer.chosenAction !== 'new_note') {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'unsupported_action' });
      continue;
    }
    const text = (answer.text ?? '').trim();
    if (text.length === 0) {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'empty' });
      continue;
    }
    try {
      const noteId = await deps.createNote(text);
      results.push({ fieldId: answer.fieldId, outcome: 'applied', noteId });
    } catch (err) {
      results.push({ fieldId: answer.fieldId, outcome: 'failed', reason: (err as Error).message });
    }
  }
  return { worksheetId: submission.worksheetId, results };
}
