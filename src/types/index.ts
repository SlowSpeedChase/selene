// Re-export database types
export { RawNote } from '../lib/db';

// Ingest workflow types
export interface IngestInput {
  title: string;
  content: string;
  created_at?: string;
  test_run?: string;
  capture_type?: string;
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

// Obsidian export types
export interface ExportableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  tags: string | null;
  word_count: number;
  concepts: string | null;
  primary_theme: string;
  secondary_themes: string | null;
  overall_sentiment: string;
  sentiment_score: number | null;
  emotional_tone: string;
  energy_level: string;
  sentiment_data: string | null;
}

export interface ExportResult {
  success: boolean;
  exported_count: number;
  errors: number;
  message: string;
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
