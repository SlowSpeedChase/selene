export type WorksheetFieldKind = 'free_capture' | 'note_review' | 'gift_surface';

export type GiftSlotRole = 'buried_treasure' | 'connection' | 'heating_up';
export type GiftReaction = 'important' | 'keep' | 'not_now' | 'let_go';

export interface GiftItem {
  noteId: number;
  title: string;
  snippet: string;
  date: string;             // YYYY-MM-DD
  slotRole: GiftSlotRole;
  connectionNote?: {        // only present when slotRole === 'connection'
    noteId: number;
    title: string;
  };
}

export interface ReviewNote {
  id: number;
  title: string;
  snippet: string;
  date: string;
}

export type ChosenAction = 'new_note' | 'acknowledge' | 'react';

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  notes?: ReviewNote[];     // note_review fields only
  gifts?: GiftItem[];       // gift_surface fields only
  binding: { action: ChosenAction };
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type WorksheetAnswer =
  | { fieldId: string; chosenAction: 'new_note' | 'acknowledge'; text?: string }
  | { fieldId: string; chosenAction: 'react'; noteId: number; reaction: GiftReaction; slotRole: GiftSlotRole };

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

export type AnswerOutcome = 'applied' | 'skipped' | 'failed' | 'acknowledged' | 'reacted';

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
  score: number;
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
