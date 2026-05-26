export type WorksheetFieldKind = 'free_capture' | 'note_review';

export interface FreeCaptureBinding {
  action: 'new_note';
}

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  binding: FreeCaptureBinding;
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type ChosenAction = 'new_note';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text: string;
}

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

export type AnswerOutcome = 'applied' | 'skipped' | 'failed';

export interface AnswerResult {
  fieldId: string;
  outcome: AnswerOutcome;
  noteId?: number;
  reason?: string;
}

export interface SubmissionResult {
  worksheetId: string;
  results: AnswerResult[];
}
