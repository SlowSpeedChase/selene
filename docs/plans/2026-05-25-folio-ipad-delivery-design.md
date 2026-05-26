# Folio iPad Delivery — Design Doc

**Date:** 2026-05-25
**Status:** Ready
**Topic:** folio, ipad, qr-code, annotation, feedback

---

## Problem

The folio Kindle workflow pushes a PDF to the device via email — zero manual navigation required. iPad has no equivalent. The user must start folio manually, find the local IP, type the URL into Safari, then navigate to the document. This friction breaks the read-annotate-feedback loop.

Folio already has full iPad support (device-detected CSS, Apple Pencil annotation canvas, `/feedback` endpoint routing back to Selene). The only missing piece is getting the iPad to the right URL without manual steps.

---

## Acceptance Criteria

- [ ] `ts-node scripts/send-ipad.ts <path-to-markdown>` works from the terminal
- [ ] A QR code appears in the terminal that opens the document directly in folio on iPad
- [ ] iPad renders the document with iPad CSS and Apple Pencil annotation canvas
- [ ] Submitting feedback from iPad routes to Selene (or saves to `~/folio/feedback/`)
- [ ] Ctrl+C cleanly kills the folio child process
- [ ] Script errors clearly if file not found or local IP cannot be determined

## ADHD Check

- Reduces friction: one command → QR code → one scan → reading
- Visible: QR code is in the terminal, hard to miss
- Externalizes cognition: annotation on iPad flows back to Selene automatically
- Scope: single script file + one npm dependency

## Scope Check

Single script file (~80 lines), one new dependency (`qrcode-terminal`). Under 1 hour of focused work.

---

## Design

### Script: `~/folio/scripts/send-ipad.ts`

Mirrors `send-report.ts` in structure.

```
CLI arg: <path-to-markdown>
    ↓
Resolve absolute path, validate file exists
    ↓
Get Mac local IP via os.networkInterfaces()
    ↓
Spawn folio server: ts-node src/server.ts --dir <projectDir> --port 3000
    ↓
Wait for server ready (poll http://localhost:3000/health or fixed delay)
    ↓
Construct URL: http://<local-ip>:3000/view/<relative-path>
    ↓
Print QR code (qrcode-terminal) + URL as plain text
    ↓
Block (process.on SIGINT/SIGTERM) → kill child process on exit
```

### New Dependency

`qrcode-terminal` — pure JS, no native binaries. Renders QR codes using Unicode block characters. Added to folio's `dependencies`.

### Feedback Loop (No Changes Required)

The folio server's existing `/feedback` POST endpoint handles everything:

```
iPad Safari → folio /view/* (iPad CSS + pencil.js canvas)
    ↓
User annotates with Apple Pencil
    ↓
POST /feedback { doc, text, annotation (SVG strokes) }
    ↓
trySeleneWebhook() → Selene if running
  else writeFeedback() → ~/folio/feedback/<timestamp>.json
```

No changes to `server.ts`, `feedback.ts`, or `pencil.ts`.

### Error Handling

| Condition | Behavior |
|-----------|----------|
| File not found | Print error, exit 1 |
| No local IPv4 address found | Print error with fallback: use `localhost` + manual IP note |
| Port 3000 already in use | Try port 3001, print actual URL used |
| folio child process crashes | Print stderr, exit 1 |

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/send-ipad.ts` | New file (created) |
| `package.json` | Add `qrcode-terminal` to dependencies |
| `package-lock.json` | Updated |

No other files require changes.

---

## Testing

1. `npm install` (pulls `qrcode-terminal`)
2. `ts-node scripts/send-ipad.ts reports/2026-05-25-selene-session.md`
3. Verify QR code appears in terminal
4. Scan with iPad camera → confirm document opens in Safari with iPad styling
5. Annotate with Apple Pencil → submit → verify `~/folio/feedback/` has the entry
6. Ctrl+C → verify no orphaned folio processes (`pgrep -f "folio"`)

---

*Designed 2026-05-25 · Folio project · companion to Kindle send-report workflow*
