import { createHash } from 'crypto';
import { createWorkflowLogger, findByContentHash, insertNote, updateCalendarEvent } from '../lib';
import { queryCalendar, pickBestEvent } from '../lib/calendar';
import type { IngestInput, IngestResult } from '../types';

const log = createWorkflowLogger('ingest');

export async function ingest(input: IngestInput): Promise<IngestResult> {
  const { title, content, created_at, test_run, capture_type } = input;

  log.info({ title, test_run }, 'Processing ingest request');

  // Generate content hash for duplicate detection
  const contentHash = createHash('sha256')
    .update(title + content)
    .digest('hex');

  // Check for duplicate
  const existing = findByContentHash(contentHash);

  if (existing) {
    log.info({ title, existingId: existing.id }, 'Duplicate detected');
    return { duplicate: true, existingId: existing.id };
  }

  // Extract tags from content
  const tags = content.match(/#\w+/g) || [];

  // Insert note
  const createdAt = created_at || new Date().toISOString();
  const id = insertNote({
    title,
    content,
    contentHash,
    tags,
    createdAt,
    testRun: test_run,
    captureType: capture_type,
  });

  // Calendar enrichment (best-effort, never blocks ingestion)
  try {
    const calendarResult = await queryCalendar(createdAt);
    if (calendarResult && calendarResult.events.length > 0) {
      const bestEvent = pickBestEvent(calendarResult.events);
      if (bestEvent) {
        updateCalendarEvent(id, bestEvent);
        log.info({ id, event: bestEvent.title, matchType: calendarResult.matchType }, 'Calendar event linked');
      }
    }
  } catch (err) {
    log.warn({ id, err }, 'Calendar enrichment failed (best-effort)');
  }

  log.info({ id, title, tags }, 'Note ingested successfully');

  return { id, duplicate: false };
}

// CLI entry point
if (require.main === module) {
  console.log('Ingest workflow - call via server or import as module');
  console.log('Usage: Import { ingest } from this file');
}
