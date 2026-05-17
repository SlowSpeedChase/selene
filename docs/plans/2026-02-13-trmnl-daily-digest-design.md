# TRMNL Daily Digest Display

**Date:** 2026-02-13
**Status:** Done
**Topic:** integrations

---

## Summary

Push the Selene daily digest to a TRMNL e-ink display each morning alongside the existing Apple Notes delivery. The condensed 3-5 bullet digest is ideal for e-ink: scannable at a glance, well under TRMNL's 2kb payload limit.

---

## Approach

Add TRMNL push to the existing `send-digest.ts` workflow. No new files, no new launchd agents. The TRMNL webhook call happens at 6am alongside Apple Notes delivery, sharing the same digest file lookup.

**Why not a separate workflow?** The logic is a single HTTP POST. A standalone workflow + launchd plist would be overengineering.

---

## Design

### Configuration

Two new env vars:

```
TRMNL_WEBHOOK_URL=        # Private plugin webhook URL (includes UUID)
TRMNL_DIGEST_ENABLED=true # Toggle independently from Apple Notes
```

In `config.ts`:

```ts
trmnlWebhookUrl: process.env.TRMNL_WEBHOOK_URL || '',
trmnlDigestEnabled: !isTestEnv && !!process.env.TRMNL_WEBHOOK_URL && process.env.TRMNL_DIGEST_ENABLED !== 'false',
```

Enabled by default when webhook URL is set. Explicitly disableable. Off in test mode.

### Push Logic (`send-digest.ts`)

A `pushToTrmnl()` function that:

1. Reads the same digest file already located by `sendDigest()`
2. Splits digest text into bullet lines
3. POSTs to the TRMNL webhook:

```json
{
  "merge_variables": {
    "title": "Selene Daily",
    "date": "Thursday, February 13, 2026",
    "bullets": ["bullet 1", "bullet 2", "bullet 3"]
  }
}
```

4. Uses native `fetch()` (Node 18+) — no new dependencies
5. Logs success/failure, does not throw (TRMNL failure must not break Apple Notes)

Called inside `sendDigest()` after the Apple Notes push. Skipped in test mode.

### TRMNL Markup Template

Configured in the TRMNL web UI (not in our codebase):

```html
<h1>{{ title }}</h1>
<p style="color: #888;">{{ date }}</p>
<hr>
{% for item in bullets %}
<p>{{ item }}</p>
{% endfor %}
```

### Error Handling

- Fire-and-forget with structured logging
- If `TRMNL_WEBHOOK_URL` is empty or disabled, skip silently
- TRMNL failure does not affect Apple Notes delivery
- Digest content is already under 2kb

---

## Acceptance Criteria

- [ ] `TRMNL_WEBHOOK_URL` env var configures the webhook endpoint
- [ ] `TRMNL_DIGEST_ENABLED` can toggle the feature on/off
- [ ] Digest is POSTed as JSON with `merge_variables` containing title, date, and bullets
- [ ] TRMNL push failure logs an error but does not prevent Apple Notes delivery
- [ ] Test mode skips the HTTP call
- [ ] `.env.example` updated with new vars

## ADHD Check

- **Reduces friction?** Yes — glanceable morning summary on e-ink, zero interaction required
- **Visible?** Yes — always-on display, literally in your field of view
- **Externalizes cognition?** Yes — key themes and action items visible without opening an app

## Scope Check

< 1 hour of implementation. Three small changes: `config.ts`, `send-digest.ts`, `.env.example`.

---

# Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Push the Selene daily digest to a TRMNL e-ink display via webhook at 6am.

**Architecture:** Add a `pushToTrmnl()` function to the existing `send-digest.ts` workflow. Config via env vars in `config.ts`. No new files, dependencies, or launchd agents.

**Tech Stack:** TypeScript, native `fetch()` (Node 22), TRMNL webhook API

---

### Task 1: Add TRMNL config to `config.ts`

**Files:**
- Modify: `src/lib/config.ts:88-89` (after `appleNotesDigestEnabled`)

**Step 1: Add TRMNL config properties**

Add after line 89 (`appleNotesDigestEnabled`):

```ts
  // TRMNL e-ink display digest
  trmnlWebhookUrl: process.env.TRMNL_WEBHOOK_URL || '',
  trmnlDigestEnabled: !isTestEnv && !!process.env.TRMNL_WEBHOOK_URL && process.env.TRMNL_DIGEST_ENABLED !== 'false',
```

**Step 2: Verify it compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat(config): add TRMNL webhook config"
```

---

### Task 2: Write the `pushToTrmnl` test

**Files:**
- Create: `src/workflows/send-digest.test.ts`

**Step 1: Write test file**

```ts
import assert from 'assert';

// Test pushToTrmnl formats and sends the correct payload
async function runTests() {
  console.log('Testing TRMNL digest push...\n');

  // Test 1: buildTrmnlPayload formats digest text into merge_variables
  console.log('Test 1: buildTrmnlPayload splits digest into bullets');
  {
    const { buildTrmnlPayload } = await import('./send-digest');
    const digest = 'Focus on thread detection refinements\nReview voice input feedback\nCheck task extraction accuracy';
    const result = buildTrmnlPayload(digest);

    assert.strictEqual(result.merge_variables.title, 'Selene Daily');
    assert.ok(result.merge_variables.date.length > 0, 'date should be non-empty');
    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Focus on thread detection refinements',
      'Review voice input feedback',
      'Check task extraction accuracy',
    ]);
    console.log('  ✓ PASS');
  }

  // Test 2: buildTrmnlPayload filters empty lines
  console.log('Test 2: buildTrmnlPayload filters empty lines');
  {
    const { buildTrmnlPayload } = await import('./send-digest');
    const digest = 'Line one\n\n\nLine two\n';
    const result = buildTrmnlPayload(digest);

    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Line one',
      'Line two',
    ]);
    console.log('  ✓ PASS');
  }

  // Test 3: buildTrmnlPayload handles single-line digest
  console.log('Test 3: buildTrmnlPayload handles single-line digest');
  {
    const { buildTrmnlPayload } = await import('./send-digest');
    const digest = 'Just one bullet today';
    const result = buildTrmnlPayload(digest);

    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Just one bullet today',
    ]);
    console.log('  ✓ PASS');
  }

  console.log('\nAll tests passed!');
}

runTests().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/send-digest.test.ts`
Expected: FAIL — `buildTrmnlPayload` is not exported from `send-digest`

---

### Task 3: Implement `buildTrmnlPayload` and `pushToTrmnl`

**Files:**
- Modify: `src/workflows/send-digest.ts`

**Step 1: Add `buildTrmnlPayload` export (after `escapeHtml` function, around line 16)**

```ts
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
```

**Step 2: Add `pushToTrmnl` function (after `buildTrmnlPayload`)**

```ts
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
```

**Step 3: Call `pushToTrmnl` inside `sendDigest()` after Apple Notes push**

In the `sendDigest()` function, after `log.info('Digest posted to Apple Notes');` (line 91), add:

```ts
    // Push to TRMNL (fire-and-forget, errors logged but don't fail the digest)
    await pushToTrmnl(message);
```

Also add a TRMNL push for the case where Apple Notes is disabled but TRMNL is enabled. After the `if (!config.appleNotesDigestEnabled)` block (line 57-60), the function currently returns early. Restructure so the digest file is read first, then Apple Notes and TRMNL are called independently. The refactored `sendDigest()` should:

1. Find and read the digest file (existing logic, lines 62-80)
2. Push to Apple Notes if enabled (existing logic)
3. Push to TRMNL if enabled (new)
4. Return result

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/workflows/send-digest.test.ts`
Expected: All 3 tests PASS

**Step 5: Verify compilation**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 6: Commit**

```bash
git add src/workflows/send-digest.ts src/workflows/send-digest.test.ts
git commit -m "feat(digest): add TRMNL e-ink display push"
```

---

### Task 4: Update `.env.example`

**Files:**
- Modify: `.env.example:84-85` (after Apple Notes section)

**Step 1: Add TRMNL config**

After line 85 (`APPLE_NOTES_DIGEST_ENABLED=true`), add:

```
# TRMNL E-Ink Display
# Webhook URL from your TRMNL private plugin (includes UUID)
# TRMNL_WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/YOUR_UUID
TRMNL_DIGEST_ENABLED=true
```

**Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: add TRMNL env vars to .env.example"
```

---

### Task 5: Manual verification

**Step 1: Set env var and run**

Add your actual TRMNL webhook URL to `.env`:
```
TRMNL_WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/YOUR_UUID
```

Run: `npx ts-node src/workflows/send-digest.ts`

Check logs for "Digest pushed to TRMNL" or error message. Verify content appears on TRMNL device on next refresh cycle.

**Step 2: Verify Apple Notes still works independently**

Run with `TRMNL_DIGEST_ENABLED=false` to confirm Apple Notes is unaffected.

**Step 3: Verify disabled behavior**

Unset `TRMNL_WEBHOOK_URL` and run. Should skip silently with no errors.
