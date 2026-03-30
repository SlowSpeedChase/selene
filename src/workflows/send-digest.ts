import { execSync } from 'child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, config } from '../lib';

const log = createWorkflowLogger('send-digest');

const DIGEST_NOTE_NAME = 'Selene Daily';

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function digestToHtml(digestText: string, date: string): string {
  const lines = digestText.split('\n').filter((l) => l.trim());
  const bodyHtml = lines.map((line) => `<p>${escapeHtml(line)}</p>`).join('\n');

  return `<h1>Selene Daily</h1>
<p style="color: #888; font-size: 14px;">Updated: ${date}</p>
<hr>
${bodyHtml}`;
}

export function buildTrmnlPayload(digestText: string): {
  merge_variables: { title: string; date: string; bullets: string[] };
} {
  const bullets = digestText.split('\n').filter((l) => l.trim());
  const date = new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
  return {
    merge_variables: {
      title: 'Selene Daily',
      date,
      bullets,
    },
  };
}

async function pushToTrmnl(digestText: string): Promise<void> {
  if (!config.trmnlDigestEnabled) {
    return;
  }

  try {
    const payload = buildTrmnlPayload(digestText);
    const response = await fetch(config.trmnlWebhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      log.error({ status: response.status, statusText: response.statusText }, 'TRMNL webhook failed');
    } else {
      log.info('Digest pushed to TRMNL');
    }
  } catch (err) {
    log.error({ err }, 'Failed to push digest to TRMNL');
  }
}

function sendViaImessage(digestText: string): void {
  if (!config.imessageDigestEnabled) {
    return;
  }

  try {
    const recipient = config.imessageDigestRecipient;
    const fullMessage = `Selene Daily Digest\n\n${digestText}`;

    // Escape for AppleScript shell embedding
    const escaped = fullMessage
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/'/g, "'\"'\"'")
      .replace(/\n/g, '\\n');

    const script = `osascript -e 'tell application "Messages"' \
      -e 'set targetService to 1st account whose service type = iMessage' \
      -e 'set targetBuddy to participant "${recipient}" of targetService' \
      -e 'send "${escaped}" to targetBuddy' \
      -e 'end tell'`;

    execSync(script, { timeout: 15000, stdio: 'pipe' });
    log.info('Digest sent via iMessage');
  } catch (err) {
    log.error({ err }, 'Failed to send digest via iMessage');
  }
}

function updateAppleNote(htmlBody: string): void {
  // Escape for AppleScript: backslashes, double quotes, single quotes, newlines
  const escaped = htmlBody
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/'/g, "'\"'\"'")
    .replace(/\n/g, '\\n');

  const script = `osascript -e 'tell application "Notes"' \
    -e 'set noteName to "${DIGEST_NOTE_NAME}"' \
    -e 'set noteBody to "${escaped}"' \
    -e 'try' \
    -e 'set targetNote to first note whose name is noteName' \
    -e 'set body of targetNote to noteBody' \
    -e 'on error' \
    -e 'make new note with properties {name:noteName, body:noteBody}' \
    -e 'end try' \
    -e 'end tell'`;

  execSync(script, { timeout: 15000, stdio: 'pipe' });
}

export async function sendDigest(): Promise<{ sent: boolean; writtenToFile?: string }> {
  log.info({ env: config.env }, 'Starting send-digest');

  // In test mode, write to file instead of posting to Apple Notes
  if (config.isTestEnv) {
    return sendDigestToFile();
  }

  // Look for today's digest, fall back to yesterday's
  const today = new Date().toISOString().split('T')[0];
  const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];

  let digestPath = join(config.digestsPath, `${today}-digest.txt`);
  if (!existsSync(digestPath)) {
    digestPath = join(config.digestsPath, `${yesterday}-digest.txt`);
  }

  if (!existsSync(digestPath)) {
    log.info('No digest file found, skipping');
    return { sent: false };
  }

  const message = readFileSync(digestPath, 'utf-8').trim();
  if (!message) {
    log.info('Empty digest, skipping');
    return { sent: false };
  }

  let anySent = false;

  // Push to Apple Notes if enabled
  if (config.appleNotesDigestEnabled) {
    try {
      const dateStr = new Date().toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      });
      const html = digestToHtml(message, dateStr);
      updateAppleNote(html);
      log.info('Digest posted to Apple Notes');
      anySent = true;
    } catch (err) {
      log.error({ err }, 'Failed to post digest to Apple Notes');
    }
  } else {
    log.info('Apple Notes digest disabled');
  }

  // Push to TRMNL if enabled (independent of Apple Notes)
  await pushToTrmnl(message);
  if (config.trmnlDigestEnabled) {
    anySent = true;
  }

  // Send via iMessage if enabled (independent of other channels)
  sendViaImessage(message);
  if (config.imessageDigestEnabled) {
    anySent = true;
  }

  return { sent: anySent };
}

/**
 * Test mode: write digest to file instead of posting to Apple Notes
 */
async function sendDigestToFile(): Promise<{ sent: boolean; writtenToFile?: string }> {
  log.info('Test mode: writing digest to file instead of Apple Notes');

  // Look for today's digest, fall back to yesterday's
  const today = new Date().toISOString().split('T')[0];
  const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];

  let digestPath = join(config.digestsPath, `${today}-digest.txt`);
  if (!existsSync(digestPath)) {
    digestPath = join(config.digestsPath, `${yesterday}-digest.txt`);
  }

  if (!existsSync(digestPath)) {
    log.info('No digest file found, skipping');
    return { sent: false };
  }

  const message = readFileSync(digestPath, 'utf-8').trim();
  if (!message) {
    log.info('Empty digest, skipping');
    return { sent: false };
  }

  // Write to sent-digests subdirectory
  const sentDir = join(config.digestsPath, 'sent');
  mkdirSync(sentDir, { recursive: true });

  const sentPath = join(sentDir, `${today}-sent.txt`);
  const fullMessage = `🌅 Selene Daily Digest\n\n${message}`;
  writeFileSync(sentPath, fullMessage);

  log.info({ path: sentPath }, 'Digest written to file (test mode)');
  return { sent: true, writtenToFile: sentPath };
}

// CLI entry point
if (require.main === module) {
  sendDigest()
    .then((result) => {
      console.log('Send digest complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Send digest failed:', err);
      process.exit(1);
    });
}
