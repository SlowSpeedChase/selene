# Folio iPad Delivery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `scripts/send-ipad.ts` to folio — run it with a Markdown file path, get a QR code in the terminal, scan with iPad to open the document in folio's browser reader with Apple Pencil annotation and Selene feedback routing.

**Architecture:** New CLI script mirrors `send-report.ts` structure. Spawns the folio server as a child process, detects Mac local IP via `os.networkInterfaces()`, polls `localhost:PORT` to confirm server readiness, then renders a QR code via `qrcode-terminal`. Blocks until Ctrl+C, then kills the child. No changes to `src/` files — the annotation/feedback loop already works.

**Tech Stack:** Node.js `child_process.spawn`, `os.networkInterfaces`, `qrcode-terminal` (new dep), existing folio server (`src/server.ts`)

---

### Task 1: Install qrcode-terminal dependency

**Files:**
- Modify: `~/folio/package.json`
- Modify: `~/folio/package-lock.json` (auto-updated)

**Step 1: Install the package**

```bash
cd ~/folio && npm install qrcode-terminal @types/qrcode-terminal --save
```

**Step 2: Verify it appears in package.json**

```bash
grep qrcode ~/folio/package.json
```

Expected output contains:
```
"qrcode-terminal": "^0.12.0",
"@types/qrcode-terminal": "^0.12.0"
```

(Exact versions may differ — just confirm both entries appear.)

**Step 3: Commit**

```bash
cd ~/folio && git add package.json package-lock.json
git commit -m "chore: add qrcode-terminal dependency for iPad delivery"
```

---

### Task 2: Write scripts/send-ipad.ts

**Files:**
- Create: `~/folio/scripts/send-ipad.ts`

**Step 1: Create the file**

```typescript
#!/usr/bin/env ts-node
/**
 * Open a folio document on iPad via QR code.
 * Usage: ts-node send-ipad.ts <path-to-markdown>
 *
 * Starts folio server, prints QR code → scan with iPad camera → opens in
 * Safari with Apple Pencil annotation. Feedback routes back to Selene.
 */

import { resolve, dirname, relative, join } from 'path';
import { existsSync, readFileSync } from 'fs';
import { spawn } from 'child_process';
import { networkInterfaces } from 'os';

// Load ~/folio/.env if present
const envPath = join(__dirname, '../.env');
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, 'utf-8').split('\n')) {
    const match = line.match(/^([A-Z_]+)=(.*)$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2].trim();
  }
}

import * as qrcode from 'qrcode-terminal';

const PORT = parseInt(process.env.FOLIO_PORT ?? '3000', 10);

function getLocalIp(): string | null {
  for (const ifaces of Object.values(networkInterfaces())) {
    for (const iface of ifaces ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return null;
}

async function waitForServer(port: number, timeoutMs = 15_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      await fetch(`http://localhost:${port}/`);
      return;
    } catch {
      await new Promise(r => setTimeout(r, 300));
    }
  }
  throw new Error(`folio server did not start within ${timeoutMs / 1000}s`);
}

async function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error('Usage: ts-node send-ipad.ts <path-to-markdown>');
    process.exit(1);
  }

  const absPath = resolve(filePath);
  if (!existsSync(absPath)) {
    console.error(`File not found: ${absPath}`);
    process.exit(1);
  }

  const localIp = getLocalIp();
  if (!localIp) {
    console.error('Could not determine local IP. Are you connected to a network?');
    process.exit(1);
  }

  const projectDir = dirname(absPath);
  const relPath = relative(projectDir, absPath);

  console.log(`Starting folio on port ${PORT}...`);
  const server = spawn(
    'npx',
    ['ts-node', 'src/server.ts', '--dir', projectDir, '--port', String(PORT)],
    {
      cwd: join(__dirname, '..'),
      stdio: 'ignore',
      detached: false,
    }
  );

  server.on('error', (err: Error) => {
    console.error('Failed to start folio:', err.message);
    process.exit(1);
  });

  try {
    await waitForServer(PORT);
  } catch (err) {
    server.kill();
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  const url = `http://${localIp}:${PORT}/view/${encodeURIComponent(relPath)}`;

  console.log('\nScan to open on iPad:\n');
  qrcode.generate(url, { small: true });
  console.log(`\n${url}\n`);
  console.log('Annotate with Apple Pencil. Tap "Send feedback" when done.');
  console.log('Press Ctrl+C to stop.\n');

  await new Promise<void>((resolve) => {
    process.on('SIGINT', resolve);
    process.on('SIGTERM', resolve);
  });

  server.kill();
  console.log('\nfolio stopped.');
}

main().catch(err => {
  console.error('Failed:', err.message);
  process.exit(1);
});
```

**Step 2: Type-check the file**

```bash
cd ~/folio && npx tsc --noEmit
```

Expected: no errors. If `qrcode-terminal` types cause issues, add to tsconfig's `typeRoots` or cast with `as any` on the generate call.

**Step 3: Commit**

```bash
cd ~/folio && git add scripts/send-ipad.ts
git commit -m "feat(ipad): add send-ipad script — QR code delivery to folio LAN reader"
```

---

### Task 3: Integration test

No automated test (consistent with `send-report.ts` — CLI entry points are not unit-tested in folio).

**Step 1: Run the script against the session report**

```bash
cd ~/folio && npx ts-node scripts/send-ipad.ts reports/2026-05-25-selene-session.md
```

Expected output:
```
Starting folio on port 3000...

Scan to open on iPad:

[QR code block in terminal]

http://192.168.x.x:3000/view/2026-05-25-selene-session.md

Annotate with Apple Pencil. Tap "Send feedback" when done.
Press Ctrl+C to stop.
```

**Step 2: Verify on iPad**

Open iPad camera, point at QR code. Confirm Safari opens and the document loads with iPad styling (not Kindle CSS — larger fonts, no e-ink margins).

**Step 3: Verify annotation canvas appears**

Scroll down in the document. Confirm the Apple Pencil annotation canvas overlay is visible (a thin toolbar at the bottom of the page).

**Step 4: Verify Ctrl+C cleanup**

Press Ctrl+C in terminal. Confirm:
- Terminal prints `folio stopped.`
- `pgrep -f "folio"` returns nothing (no orphaned processes)

**Step 5: Test error cases**

```bash
# File not found
npx ts-node scripts/send-ipad.ts nonexistent.md
# Expected: "File not found: ..." exit 1

# No args
npx ts-node scripts/send-ipad.ts
# Expected: "Usage: ..." exit 1
```

---

### Notes

- **Port conflict:** If port 3000 is in use (e.g., another folio instance), the script will hang at `waitForServer` and eventually time out with a clear message. Kill the other process or set `FOLIO_PORT=3001` in the env.
- **Same WiFi required:** The QR code URL uses the Mac's LAN IP. iPad must be on the same WiFi network to reach it.
- **Feedback target:** If Selene's webhook server is running at `localhost:5678`, feedback submits there via `trySeleneWebhook()`. If not, feedback saves to `~/folio/feedback/` as JSON.
