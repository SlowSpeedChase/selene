// @map purpose: Build the daily review worksheet and apply its answers (capture/acknowledge) for the iPad
// @map reads: raw_notes (via injected route deps)
// @map writes: raw_notes (new notes, via injected route deps)
// @map trigger: server routes (GET /api/worksheets/today, POST /api/worksheets/:id/answers)
import type {
  Worksheet,
  WorksheetSubmission,
  SubmissionResult,
  AnswerResult,
  RelatedNote,
  RelatedNotesGroup,
  ReviewNote,
  GiftItem,
} from '../types/worksheets';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'generate-worksheet' });

// ---------------------------------------------------------------------------
// buildTodayWorksheet
// ---------------------------------------------------------------------------

export interface BuildDeps {
  fetchReviewNotes?: () => Promise<ReviewNote[]>;
  fetchGiftItems?: () => Promise<GiftItem[]>;
}

const defaultBuildDeps: BuildDeps = {};

export async function buildTodayWorksheet(
  now: Date = new Date(),
  deps: BuildDeps = defaultBuildDeps,
): Promise<Worksheet> {
  const date = now.toISOString().slice(0, 10);

  const [reviewNotes, giftItems] = await Promise.all([
    deps.fetchReviewNotes?.() ?? Promise.resolve([]),
    deps.fetchGiftItems?.() ?? Promise.resolve([]),
  ]);

  const fields: Worksheet['fields'] = [];

  if (giftItems.length > 0) {
    fields.push({
      id: 'f_gift',
      kind: 'gift_surface',
      prompt: 'things i noticed for you',
      gifts: giftItems,
      binding: { action: 'react' },
    });
  }

  fields.push(
    {
      id: 'f1',
      kind: 'free_capture',
      prompt: "Anything on your mind? Write it and it'll become a note.",
      binding: { action: 'new_note' },
    },
    {
      id: 'f2',
      kind: 'free_capture',
      prompt: 'One thing to get done today?',
      binding: { action: 'new_note' },
    },
  );

  if (reviewNotes.length > 0) {
    fields.push({
      id: 'f3',
      kind: 'note_review',
      prompt: 'These notes need attention:',
      notes: reviewNotes,
      binding: { action: 'acknowledge' },
    });
  }

  return {
    id: `ws_${date}`,
    title: `Daily Review — ${date}`,
    fields,
  };
}

// ---------------------------------------------------------------------------
// applyWorksheetAnswers
// ---------------------------------------------------------------------------

export interface ApplyDeps {
  createNote: (text: string) => Promise<number>;
  findRelatedNotes?: (text: string, excludeId: number) => Promise<RelatedNote[]>;
}

export async function applyWorksheetAnswers(
  submission: WorksheetSubmission,
  deps: ApplyDeps,
): Promise<SubmissionResult> {
  const results: AnswerResult[] = [];
  const relatedNotes: RelatedNotesGroup[] = [];

  for (const answer of submission.answers) {
    if (answer.chosenAction === 'acknowledge') {
      results.push({ fieldId: answer.fieldId, outcome: 'acknowledged' });
      continue;
    }

    if (answer.chosenAction !== 'new_note') {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'unsupported_action' });
      continue;
    }

    const text = (answer.text ?? '').trim();
    if (text.length === 0) {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'empty' });
      continue;
    }

    let noteId: number;
    try {
      noteId = await deps.createNote(text);
      results.push({ fieldId: answer.fieldId, outcome: 'applied', noteId });
    } catch (err) {
      results.push({ fieldId: answer.fieldId, outcome: 'failed', reason: (err as Error).message });
      continue;
    }

    if (deps.findRelatedNotes) {
      try {
        const matches = await deps.findRelatedNotes(text, noteId);
        if (matches.length > 0) {
          relatedNotes.push({ fieldId: answer.fieldId, matches });
        }
      } catch (err) {
        log.warn({ err, fieldId: answer.fieldId }, 'findRelatedNotes failed — skipping context');
      }
    }
  }

  return { worksheetId: submission.worksheetId, results, relatedNotes };
}
