# iMessage Daily Digest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Send a condensed daily digest via iMessage at 6am using AppleScript.

**Architecture:** `daily-summary.ts` (midnight) writes a condensed digest file → `send-digest.ts` (6am) reads it and sends via `osascript`. Two launchd jobs, loosely coupled via a text file.

**Tech Stack:** TypeScript, Ollama (mistral:7b), osascript/AppleScript, launchd

---

### Task 1: Add digest config to config.ts

**Files:**
- Modify: `src/lib/config.ts`

**Step 1: Add iMessage config fields**

Add to the config object in `src/lib/config.ts`:

```typescript
// iMessage digest
imessageDigestTo: process.env.IMESSAGE_DIGEST_TO || '',
imessageDigestEnabled: process.env.IMESSAGE_DIGEST_ENABLED !== 'false',
digestsPath: join(projectRoot, 'data', 'digests'),
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat: add iMessage digest config"
```

---

### Task 2: Add condensed digest generation to daily-summary.ts

**Files:**
- Modify: `src/workflows/daily-summary.ts`

**Step 1: Add digest file generation after Obsidian write**

After the existing `writeFileSync(outputPath, markdown)` line, add:

```typescript
import { config } from '../lib';

// Generate condensed digest for iMessage
const DIGEST_PROMPT = `Condense this daily summary into 3-5 short bullet points for a text message.
Be brief and actionable. No headers or formatting. No bullet characters - just short lines.

{summary}`;

let digest: string;
if (await isAvailable()) {
  digest = await generate(DIGEST_PROMPT.replace('{summary}', summary));
} else {
  digest = `${notes.length} notes captured. Themes: ${themesText}`;
}

// Write digest file
const digestDir = config.digestsPath;
if (!existsSync(digestDir)) {
  mkdirSync(digestDir, { recursive: true });
}
const digestPath = join(digestDir, `${dateStr}-digest.txt`);
writeFileSync(digestPath, digest);
log.info({ digestPath }, 'Condensed digest written');
```

Update the return type to include `digestPath`:

```typescript
return { success: true, path: outputPath, digestPath };
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/daily-summary.ts
git commit -m "feat: generate condensed digest file in daily-summary"
```

---

### Task 3: Create send-digest.ts workflow

**Files:**
- Create: `src/workflows/send-digest.ts`

**Step 1: Write the send-digest workflow**

```typescript
import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, config } from '../lib';

const log = createWorkflowLogger('send-digest');

function sendIMessage(to: string, message: string): void {
  // Escape for AppleScript string
  const escaped = message
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n');

  const script = `
    tell application "Messages"
      set targetService to 1st account whose service type = iMessage
      set targetBuddy to participant "${to}" of targetService
      send "${escaped}" to targetBuddy
    end tell
  `;

  execSync(`osascript -e '${script.replace(/'/g, "'\\''")}'`, {
    timeout: 30000,
  });
}

export async function sendDigest(): Promise<{ sent: boolean }> {
  log.info('Starting send-digest');

  if (!config.imessageDigestEnabled) {
    log.info('iMessage digest disabled');
    return { sent: false };
  }

  if (!config.imessageDigestTo) {
    log.warn('IMESSAGE_DIGEST_TO not configured');
    return { sent: false };
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

  try {
    sendIMessage(config.imessageDigestTo, `🌅 Selene Daily Digest\n\n${message}`);
    log.info({ to: config.imessageDigestTo }, 'Digest sent via iMessage');
    return { sent: true };
  } catch (err) {
    log.error({ err }, 'Failed to send iMessage digest');
    return { sent: false };
  }
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
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/send-digest.ts
git commit -m "feat: add send-digest workflow for iMessage delivery"
```

---

### Task 4: Create launchd plist for 6am send

**Files:**
- Create: `launchd/com.selene.send-digest.plist`

**Step 1: Write the plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.send-digest</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>src/workflows/send-digest.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/send-digest.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/send-digest.error.log</string>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add launchd/com.selene.send-digest.plist
git commit -m "feat: add launchd plist for 6am digest send"
```

---

### Task 5: Update .env.example and documentation

**Files:**
- Modify: `.env.example` (if it exists, otherwise skip)
- Modify: `CLAUDE.md` (add send-digest to launchd listing)

**Step 1: Add env vars to .env.example**

```
# iMessage Daily Digest
IMESSAGE_DIGEST_TO=+1XXXXXXXXXX
IMESSAGE_DIGEST_ENABLED=true
```

**Step 2: Update CLAUDE.md launchd section**

Add to the launchd listing:
```
com.selene.send-digest.plist        # Daily at 6am
```

Add to workflow operations:
```bash
npx ts-node src/workflows/send-digest.ts
```

**Step 3: Commit**

```bash
git add .env.example CLAUDE.md
git commit -m "docs: add iMessage digest config and commands"
```

---

### Task 6: Manual test

**Step 1: Create a test digest file**

```bash
mkdir -p data/digests
echo "Focus was scattered across 3 projects yesterday
Thread on ADHD tooling gained a new connection
2 tasks extracted, both marked actionable
Consider consolidating the productivity notes" > data/digests/$(date +%Y-%m-%d)-digest.txt
```

**Step 2: Run send-digest manually**

```bash
IMESSAGE_DIGEST_TO="+1XXXXXXXXXX" npx ts-node src/workflows/send-digest.ts
```

Expected: iMessage received on phone.

**Step 3: Clean up test file**

```bash
rm data/digests/$(date +%Y-%m-%d)-digest.txt
```
