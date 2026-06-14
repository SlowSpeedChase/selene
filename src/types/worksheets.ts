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

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  notes?: ReviewNote[];     // note_review fields only
  gifts?: GiftItem[];       // gift_surface fields only
  binding: { action: 'new_note' | 'acknowledge' | 'react' };
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type ChosenAction = 'new_note' | 'acknowledge' | 'react';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text?: string;             // free_capture
  noteId?: number;           // react answers — which gift card
  reaction?: GiftReaction;   // react answers — which tap
  slotRole?: GiftSlotRole;   // react answers — echoed back from the gift item
}

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
