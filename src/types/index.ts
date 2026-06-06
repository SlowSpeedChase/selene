// Re-export database types
export { RawNote } from '../lib/db';

// Ingest workflow types
// Cross-repo contract: also consumed by Folio's trySeleneWebhook.
// KEEP IN SYNC with folio `src/feedback.ts` → SeleneDraftPayload (~/folio).
export interface IngestInput {
  title: string;
  content: string;
  created_at?: string;
  test_run?: string;
  capture_type?: string;
  source_uuid?: string;
}

export interface IngestResult {
  id?: number;
  duplicate: boolean;
  existingId?: number;
}

// Webhook response types
export interface WebhookResponse {
  status: 'created' | 'duplicate' | 'error';
  id?: number;
  message?: string;
}

// Workflow result types
export interface WorkflowResult {
  processed: number;
  errors: number;
  details: Array<{ id: number; success: boolean; error?: string }>;
}

// Calendar event context (from selene-calendar CLI)
export interface CalendarEvent {
  title: string;
  startDate: string;  // ISO 8601
  endDate: string;
  calendar: string;
  isAllDay: boolean;
}

export interface CalendarLookupResult {
  events: CalendarEvent[];
  matchType: 'during' | 'just_ended' | 'none';
}
