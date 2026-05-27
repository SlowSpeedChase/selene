export type WorksheetFieldKind = 'free_capture' | 'note_review';

export interface ReviewNote {
  id: number;
  title: string;
  snippet: string;
  date: string;  // ISO date string YYYY-MM-DD
}

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  notes?: ReviewNote[];                      // only on note_review fields
  binding: { action: 'new_note' | 'acknowledge' };
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type ChosenAction = 'new_note' | 'acknowledge';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text: string;
}

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

export type AnswerOutcome = 'applied' | 'skipped' | 'failed' | 'acknowledged';

export interface AnswerResult {
  fieldId: string;
  outcome: AnswerOutcome;
  noteId?: number;
  reason?: string;
}

export interface RelatedNote {
  noteId: number;
  title: string;
  snippet: string;
  date: string;
  score: number;    // 0–1, derived from L2 distance
}

export interface RelatedNotesGroup {
  fieldId: string;
  matches: RelatedNote[];
}

export interface SubmissionResult {
  worksheetId: string;
  results: AnswerResult[];
  relatedNotes: RelatedNotesGroup[];
}
