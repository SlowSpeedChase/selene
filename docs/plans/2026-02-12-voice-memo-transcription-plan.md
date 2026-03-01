# Voice Memo Transcription Pipeline — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically transcribe Apple Voice Memos via whisper.cpp and ingest them into Selene's pipeline.

**Architecture:** A launchd `WatchPaths` agent triggers a TypeScript workflow when new `.m4a` files appear in the Voice Memos directory. The workflow converts audio to WAV, runs whisper.cpp, saves a markdown transcript, archives the original, and POSTs to Selene's webhook. A JSON manifest prevents double-processing.

**Tech Stack:** TypeScript (Node.js child_process), whisper.cpp (Metal), ffmpeg, launchd, existing Selene libs (logger, config)

**Design Doc:** `docs/plans/2026-02-12-voice-memo-transcription-design.md`

---

### Task 1: Setup Script — Install whisper.cpp + Model

**Files:**
- Create: `scripts/setup-whisper.sh`

**Step 1: Write the setup script**

```bash
#!/bin/bash
#
# Setup whisper.cpp for Voice Memo transcription
#
# Installs whisper.cpp with Metal acceleration, downloads the medium model,
# creates output directories, and installs the launchd agent.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

WHISPER_DIR="$HOME/.local/whisper.cpp"
MODEL_NAME="ggml-medium.bin"
MODEL_DIR="$WHISPER_DIR/models"
VOICE_MEMOS_DIR="$HOME/VoiceMemos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "  Selene Voice Memo Transcription Setup"
echo "========================================"
echo ""

# Step 1: Check prerequisites
echo "Step 1: Checking prerequisites..."
echo "----------------------------------------"

# Check Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}ERROR: This script requires Apple Silicon (arm64). Detected: $ARCH${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Apple Silicon detected"

# Check Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo -e "${YELLOW}Installing Xcode Command Line Tools...${NC}"
    xcode-select --install
    echo "Re-run this script after Xcode CLI tools finish installing."
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Xcode CLI tools installed"

# Check cmake
if ! command -v cmake &>/dev/null; then
    echo -e "${YELLOW}cmake not found. Installing via Homebrew...${NC}"
    if ! command -v brew &>/dev/null; then
        echo -e "${RED}ERROR: Homebrew not installed. Install from https://brew.sh${NC}"
        exit 1
    fi
    brew install cmake
fi
echo -e "  ${GREEN}✓${NC} cmake available"

# Check ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    echo -e "${YELLOW}ffmpeg not found. Installing via Homebrew...${NC}"
    if ! command -v brew &>/dev/null; then
        echo -e "${RED}ERROR: Homebrew not installed. Install from https://brew.sh${NC}"
        exit 1
    fi
    brew install ffmpeg
fi
echo -e "  ${GREEN}✓${NC} ffmpeg available"
echo ""

# Step 2: Install whisper.cpp
echo "Step 2: Installing whisper.cpp..."
echo "----------------------------------------"

if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
    echo -e "  ${GREEN}✓${NC} whisper.cpp already installed at $WHISPER_DIR"
else
    mkdir -p "$HOME/.local"

    if [ -d "$WHISPER_DIR" ]; then
        echo "  Updating existing clone..."
        cd "$WHISPER_DIR" && git pull
    else
        echo "  Cloning whisper.cpp..."
        git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    fi

    echo "  Building with Metal acceleration..."
    cd "$WHISPER_DIR"
    cmake -B build -DWHISPER_METAL=ON
    cmake --build build -j$(sysctl -n hw.ncpu) --config Release

    if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
        echo -e "  ${GREEN}✓${NC} whisper.cpp built successfully"
    else
        echo -e "${RED}ERROR: Build failed. Check output above.${NC}"
        exit 1
    fi
fi
echo ""

# Step 3: Download model
echo "Step 3: Downloading model ($MODEL_NAME)..."
echo "----------------------------------------"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/$MODEL_NAME" ]; then
    echo -e "  ${GREEN}✓${NC} Model already downloaded"
else
    echo "  Downloading medium model (~1.5GB)..."
    cd "$WHISPER_DIR"
    bash models/download-ggml-model.sh medium
    echo -e "  ${GREEN}✓${NC} Model downloaded"
fi
echo ""

# Step 4: Create output directories
echo "Step 4: Creating output directories..."
echo "----------------------------------------"

mkdir -p "$VOICE_MEMOS_DIR/archive"
mkdir -p "$VOICE_MEMOS_DIR/transcripts"

if [ ! -f "$VOICE_MEMOS_DIR/.processed.json" ]; then
    echo '{"files":{}}' > "$VOICE_MEMOS_DIR/.processed.json"
    echo -e "  ${GREEN}✓${NC} Initialized .processed.json"
else
    echo -e "  ${GREEN}✓${NC} .processed.json already exists"
fi

echo -e "  ${GREEN}✓${NC} ~/VoiceMemos/archive/"
echo -e "  ${GREEN}✓${NC} ~/VoiceMemos/transcripts/"
echo ""

# Step 5: Install launchd agent
echo "Step 5: Installing launchd agent..."
echo "----------------------------------------"

PLIST_SRC="$PROJECT_DIR/launchd/com.selene.transcribe-voice-memos.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.selene.transcribe-voice-memos.plist"

if [ ! -f "$PLIST_SRC" ]; then
    echo -e "  ${RED}ERROR: Plist not found at $PLIST_SRC${NC}"
    echo "  Run the full Selene install first, or create the plist."
    exit 1
fi

# Unload if already loaded
if [ -f "$PLIST_DST" ]; then
    launchctl unload "$PLIST_DST" 2>/dev/null || true
fi

cp "$PLIST_SRC" "$PLIST_DST"
launchctl load "$PLIST_DST"
echo -e "  ${GREEN}✓${NC} Agent installed and loaded"
echo ""

# Step 6: Smoke test
echo "Step 6: Smoke test..."
echo "----------------------------------------"

# Generate a 1-second silent WAV
TEMP_WAV=$(mktemp /tmp/whisper-test-XXXXXX.wav)
ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -c:a pcm_s16le "$TEMP_WAV" -y 2>/dev/null

if "$WHISPER_DIR/build/bin/whisper-cli" \
    -m "$MODEL_DIR/$MODEL_NAME" \
    -f "$TEMP_WAV" \
    --no-timestamps \
    -t 4 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Whisper transcription works"
else
    echo -e "${RED}ERROR: Whisper smoke test failed${NC}"
    rm -f "$TEMP_WAV"
    exit 1
fi

rm -f "$TEMP_WAV"
echo ""

echo "========================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "========================================"
echo ""
echo "Voice Memos will be automatically transcribed."
echo ""
echo "Output:"
echo "  Transcripts: ~/VoiceMemos/transcripts/"
echo "  Archives:    ~/VoiceMemos/archive/"
echo "  Manifest:    ~/VoiceMemos/.processed.json"
echo ""
echo "Logs:"
echo "  $PROJECT_DIR/logs/transcribe-voice-memos.log"
echo "  $PROJECT_DIR/logs/transcribe-voice-memos.error.log"
echo ""
```

**Step 2: Make it executable and verify syntax**

Run: `chmod +x scripts/setup-whisper.sh && bash -n scripts/setup-whisper.sh`
Expected: No output (syntax OK)

**Step 3: Commit**

```bash
git add scripts/setup-whisper.sh
git commit -m "feat: add whisper.cpp setup script for voice memo transcription"
```

---

### Task 2: Add Voice Memos Config

**Files:**
- Modify: `src/lib/config.ts:60-88`

**Step 1: Add voice memos config to the exported config object**

Add these lines inside the `config` object, after the `imessageDigestEnabled` line:

```typescript
  // Voice Memos transcription
  voiceMemosRecordingsDir:
    process.env.VOICE_MEMOS_RECORDINGS_DIR ||
    join(
      homedir(),
      'Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings'
    ),
  voiceMemosOutputDir: process.env.VOICE_MEMOS_OUTPUT_DIR || join(homedir(), 'VoiceMemos'),
  whisperBinary:
    process.env.WHISPER_BINARY || join(homedir(), '.local/whisper.cpp/build/bin/whisper-cli'),
  whisperModel:
    process.env.WHISPER_MODEL ||
    join(homedir(), '.local/whisper.cpp/models/ggml-medium.bin'),
  whisperThreads: parseInt(process.env.WHISPER_THREADS || '6', 10),
  seleneWebhookUrl:
    process.env.SELENE_WEBHOOK_URL || 'http://localhost:5678/webhook/api/drafts',
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/lib/config.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat: add voice memos config paths (whisper, recordings, output)"
```

---

### Task 3: Add Voice Memo Types

**Files:**
- Modify: `src/types/index.ts`

**Step 1: Add types at the end of the file**

```typescript
// Voice memo transcription types
export interface ProcessedFileEntry {
  transcribedAt: string;
  archivedTo: string;
  markdownPath: string;
  ingestedToSelene: boolean;
}

export interface ProcessedManifest {
  files: Record<string, ProcessedFileEntry>;
}

export interface TranscriptionResult {
  filename: string;
  text: string;
  duration: string;
  archivedTo: string;
  markdownPath: string;
  ingestedToSelene: boolean;
}

export interface VoiceMemoWorkflowResult {
  processed: number;
  errors: number;
  retried: number;
  details: Array<{ filename: string; success: boolean; error?: string }>;
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/types/index.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/types/index.ts
git commit -m "feat: add voice memo transcription types"
```

---

### Task 4: Write the Transcription Workflow

**Files:**
- Create: `src/workflows/transcribe-voice-memos.ts`

**Step 1: Write the workflow**

```typescript
import { execSync } from 'child_process';
import {
  readFileSync,
  writeFileSync,
  existsSync,
  mkdirSync,
  copyFileSync,
  readdirSync,
  statSync,
} from 'fs';
import { join, basename } from 'path';
import { tmpdir } from 'os';
import { createWorkflowLogger, config } from '../lib';
import type { ProcessedManifest, VoiceMemoWorkflowResult } from '../types';

const log = createWorkflowLogger('transcribe-voice-memos');

const STALE_SECONDS = 5;
const MIN_FILE_SIZE = 1024; // 1KB
const TRANSCRIBE_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes

// --- Manifest management ---

function loadManifest(): ProcessedManifest {
  const manifestPath = join(config.voiceMemosOutputDir, '.processed.json');
  if (!existsSync(manifestPath)) {
    return { files: {} };
  }
  try {
    return JSON.parse(readFileSync(manifestPath, 'utf-8'));
  } catch (err) {
    log.warn({ err }, 'Failed to parse manifest, starting fresh');
    return { files: {} };
  }
}

function saveManifest(manifest: ProcessedManifest): void {
  const manifestPath = join(config.voiceMemosOutputDir, '.processed.json');
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
}

// --- Audio helpers ---

function isFileReady(filePath: string): boolean {
  try {
    const stats = statSync(filePath);
    if (stats.size < MIN_FILE_SIZE) return false;
    const ageMs = Date.now() - stats.mtimeMs;
    return ageMs > STALE_SECONDS * 1000;
  } catch {
    return false;
  }
}

function getAudioDuration(filePath: string): string {
  try {
    const output = execSync(
      `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${filePath}"`,
      { encoding: 'utf-8', timeout: 10000 }
    ).trim();
    const totalSeconds = Math.round(parseFloat(output));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}m ${seconds}s`;
  } catch {
    return 'unknown';
  }
}

function convertToWav(m4aPath: string): string {
  const wavPath = join(tmpdir(), `selene-whisper-${Date.now()}.wav`);
  execSync(
    `ffmpeg -i "${m4aPath}" -ar 16000 -ac 1 -c:a pcm_s16le "${wavPath}" -y`,
    { stdio: 'pipe', timeout: 120000 }
  );
  return wavPath;
}

function transcribeWav(wavPath: string): string {
  const output = execSync(
    `"${config.whisperBinary}" -m "${config.whisperModel}" -f "${wavPath}" --no-timestamps -t ${config.whisperThreads} -l en`,
    { encoding: 'utf-8', timeout: TRANSCRIBE_TIMEOUT_MS, stdio: ['pipe', 'pipe', 'pipe'] }
  );
  // whisper.cpp outputs text to stdout, sometimes with leading/trailing whitespace
  return output.trim();
}

function cleanupTempFile(filePath: string): void {
  try {
    if (existsSync(filePath)) {
      execSync(`rm "${filePath}"`, { stdio: 'pipe' });
    }
  } catch {
    // Best effort
  }
}

// --- Filename parsing ---

function parseFilename(filename: string): { date: string; friendlyName: string; archiveName: string } {
  // Voice Memos format: "20260212 153045.m4a" or "20260212 153045-HEXID.m4a"
  // Also handles user-renamed files
  const base = basename(filename, '.m4a');
  const dateMatch = base.match(/^(\d{4})(\d{2})(\d{2})\s+(\d{2})(\d{2})(\d{2})/);

  if (dateMatch) {
    const [, year, month, day, hour, min, sec] = dateMatch;
    const date = `${year}-${month}-${day}`;
    const time = `${hour}:${min}:${sec}`;
    const friendlyName = `${date} ${time}`;
    const archiveName = `${date}-${hour}${min}${sec}`;
    return { date, friendlyName, archiveName };
  }

  // Fallback: use file modification time
  const now = new Date();
  const date = now.toISOString().split('T')[0];
  const friendlyName = base || 'untitled';
  const archiveName = `${date}-${friendlyName.replace(/[^a-zA-Z0-9-]/g, '_')}`;
  return { date, friendlyName, archiveName };
}

// --- Markdown generation ---

function generateMarkdown(
  friendlyName: string,
  date: string,
  duration: string,
  archivePath: string,
  transcription: string
): string {
  return `# Voice Memo: ${friendlyName}

**Recorded:** ${date}
**Duration:** ${duration}
**Audio:** [Original recording](${archivePath})

---

${transcription}
`;
}

// --- Selene ingestion ---

async function postToSelene(title: string, content: string): Promise<boolean> {
  try {
    const response = await fetch(config.seleneWebhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title,
        content,
        tags: ['voice-memo'],
        source: 'voice-memos',
      }),
    });
    if (!response.ok) {
      log.error({ status: response.status }, 'Webhook POST failed');
      return false;
    }
    return true;
  } catch (err) {
    log.error({ err }, 'Webhook POST error');
    return false;
  }
}

// --- Notification ---

function notifyError(message: string): void {
  try {
    execSync(
      `osascript -e 'display notification "${message}" with title "Selene Voice Memos" sound name "Basso"'`,
      { stdio: 'pipe', timeout: 5000 }
    );
  } catch {
    // Best effort
  }
}

// --- Preflight checks ---

function preflightCheck(): boolean {
  if (!existsSync(config.whisperBinary)) {
    const msg = 'whisper.cpp not installed. Run scripts/setup-whisper.sh';
    log.error(msg);
    notifyError(msg);
    return false;
  }
  if (!existsSync(config.whisperModel)) {
    const msg = 'Whisper model not found. Run scripts/setup-whisper.sh';
    log.error(msg);
    notifyError(msg);
    return false;
  }
  try {
    execSync('which ffmpeg', { stdio: 'pipe' });
  } catch {
    const msg = 'ffmpeg not installed. Run: brew install ffmpeg';
    log.error(msg);
    notifyError(msg);
    return false;
  }
  return true;
}

// --- Main workflow ---

export async function transcribeVoiceMemos(): Promise<VoiceMemoWorkflowResult> {
  log.info('Starting voice memo transcription run');

  const result: VoiceMemoWorkflowResult = {
    processed: 0,
    errors: 0,
    retried: 0,
    details: [],
  };

  if (!preflightCheck()) {
    return result;
  }

  // Ensure output directories exist
  const archiveDir = join(config.voiceMemosOutputDir, 'archive');
  const transcriptsDir = join(config.voiceMemosOutputDir, 'transcripts');
  mkdirSync(archiveDir, { recursive: true });
  mkdirSync(transcriptsDir, { recursive: true });

  const manifest = loadManifest();
  const recordingsDir = config.voiceMemosRecordingsDir;

  if (!existsSync(recordingsDir)) {
    log.warn({ recordingsDir }, 'Recordings directory not found');
    return result;
  }

  // Scan for new .m4a files
  const allFiles = readdirSync(recordingsDir).filter((f) => f.endsWith('.m4a'));
  const newFiles = allFiles.filter((f) => !manifest.files[f] && isFileReady(join(recordingsDir, f)));

  log.info({ total: allFiles.length, new: newFiles.length }, 'Scanned recordings directory');

  // Process new files
  for (const filename of newFiles) {
    const filePath = join(recordingsDir, filename);
    let wavPath: string | null = null;

    try {
      log.info({ filename }, 'Processing voice memo');

      const { date, friendlyName, archiveName } = parseFilename(filename);
      const duration = getAudioDuration(filePath);

      // Convert to WAV
      wavPath = convertToWav(filePath);

      // Transcribe
      const transcription = transcribeWav(wavPath);
      log.info({ filename, chars: transcription.length }, 'Transcription complete');

      // Archive original
      const archivePath = join(archiveDir, `${archiveName}.m4a`);
      copyFileSync(filePath, archivePath);

      // Write markdown
      const title = `Voice Memo: ${friendlyName}`;
      const markdownPath = join(transcriptsDir, `${archiveName}.md`);
      const markdown = generateMarkdown(friendlyName, date, duration, archivePath, transcription);
      writeFileSync(markdownPath, markdown);

      // POST to Selene
      const ingested = await postToSelene(title, transcription);

      // Update manifest
      manifest.files[filename] = {
        transcribedAt: new Date().toISOString(),
        archivedTo: archivePath,
        markdownPath,
        ingestedToSelene: ingested,
      };
      saveManifest(manifest);

      result.processed++;
      result.details.push({ filename, success: true });
      log.info({ filename, ingested }, 'Voice memo processed');
    } catch (err) {
      const error = err as Error;
      result.errors++;
      result.details.push({ filename, success: false, error: error.message });
      log.error({ err: error, filename }, 'Failed to process voice memo');
      notifyError(`Failed to transcribe: ${filename}`);
    } finally {
      if (wavPath) cleanupTempFile(wavPath);
    }
  }

  // Retry failed Selene ingestions
  for (const [filename, entry] of Object.entries(manifest.files)) {
    if (!entry.ingestedToSelene && existsSync(entry.markdownPath)) {
      try {
        const markdown = readFileSync(entry.markdownPath, 'utf-8');
        // Extract transcription text (everything after the --- separator)
        const parts = markdown.split('\n---\n');
        const transcription = parts.length > 1 ? parts[parts.length - 1].trim() : markdown;
        const { friendlyName } = parseFilename(filename);
        const title = `Voice Memo: ${friendlyName}`;

        const ingested = await postToSelene(title, transcription);
        if (ingested) {
          entry.ingestedToSelene = true;
          saveManifest(manifest);
          result.retried++;
          log.info({ filename }, 'Retried Selene ingestion succeeded');
        }
      } catch (err) {
        log.warn({ err, filename }, 'Retry failed');
      }
    }
  }

  log.info(
    { processed: result.processed, errors: result.errors, retried: result.retried },
    'Voice memo transcription run complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  transcribeVoiceMemos()
    .then((result) => {
      console.log('Voice memo transcription complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Voice memo transcription failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/workflows/transcribe-voice-memos.ts`
Expected: No errors (or only pre-existing errors from other files)

**Step 3: Commit**

```bash
git add src/workflows/transcribe-voice-memos.ts
git commit -m "feat: add voice memo transcription workflow"
```

---

### Task 5: Create launchd Plist

**Files:**
- Create: `launchd/com.selene.transcribe-voice-memos.plist`

**Step 1: Write the plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.transcribe-voice-memos</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>src/workflows/transcribe-voice-memos.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <key>WatchPaths</key>
    <array>
        <string>/Users/chaseeasterling/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings</string>
    </array>

    <key>ThrottleInterval</key>
    <integer>10</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/transcribe-voice-memos.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/transcribe-voice-memos.error.log</string>
</dict>
</plist>
```

Note: `/opt/homebrew/bin` is included in PATH because Apple Silicon Homebrew installs there (needed for ffmpeg and cmake).

**Step 2: Validate plist XML**

Run: `plutil -lint launchd/com.selene.transcribe-voice-memos.plist`
Expected: `launchd/com.selene.transcribe-voice-memos.plist: OK`

**Step 3: Commit**

```bash
git add launchd/com.selene.transcribe-voice-memos.plist
git commit -m "feat: add launchd plist for voice memo file watcher"
```

---

### Task 6: Update install-launchd.sh

**Files:**
- Modify: `scripts/install-launchd.sh:37-47`

**Step 1: Add the new agent to the AGENTS array**

Add `"com.selene.transcribe-voice-memos"` as the last entry in the array:

```bash
AGENTS=(
    "com.selene.server"
    "com.selene.process-llm"
    "com.selene.extract-tasks"
    "com.selene.compute-embeddings"
    "com.selene.compute-associations"
    "com.selene.daily-summary"
    "com.selene.export-obsidian"
    "com.selene.detect-threads"
    "com.selene.reconsolidate-threads"
    "com.selene.transcribe-voice-memos"
)
```

**Step 2: Verify syntax**

Run: `bash -n scripts/install-launchd.sh`
Expected: No output (syntax OK)

**Step 3: Commit**

```bash
git add scripts/install-launchd.sh
git commit -m "feat: add voice memo agent to launchd installer"
```

---

### Task 7: End-to-End Manual Test

**Step 1: Run setup script**

Run: `./scripts/setup-whisper.sh`
Expected: All 6 steps pass with green checkmarks. Smoke test succeeds.

**Step 2: Verify Selene server is running**

Run: `curl -s http://localhost:5678/health`
Expected: Health check returns OK

**Step 3: Test with an existing voice memo**

Run the workflow manually:

```bash
npx ts-node src/workflows/transcribe-voice-memos.ts
```

Expected:
- Console output shows files scanned, one or more processed
- `~/VoiceMemos/transcripts/` contains a new `.md` file with transcription
- `~/VoiceMemos/archive/` contains a copy of the `.m4a`
- `~/VoiceMemos/.processed.json` shows the processed entry
- Selene webhook received the note (check `logs/server.out.log`)

**Step 4: Run again to verify idempotency**

Run: `npx ts-node src/workflows/transcribe-voice-memos.ts`
Expected: "0 new files" — already-processed files are skipped

**Step 5: Verify launchd agent is loaded**

Run: `launchctl list | grep transcribe-voice-memos`
Expected: Shows the agent with PID or exit status

**Step 6: Test live trigger — record a new Voice Memo on your Mac, wait ~15 seconds**

Expected: The launchd agent fires, transcribes the new memo, saves markdown, archives original, and ingests into Selene.

**Step 7: Final commit**

```bash
git add -A
git commit -m "feat: voice memo transcription pipeline complete"
```

---

### Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Setup script | `scripts/setup-whisper.sh` |
| 2 | Config additions | `src/lib/config.ts` |
| 3 | Type definitions | `src/types/index.ts` |
| 4 | Main workflow | `src/workflows/transcribe-voice-memos.ts` |
| 5 | launchd plist | `launchd/com.selene.transcribe-voice-memos.plist` |
| 6 | Install script update | `scripts/install-launchd.sh` |
| 7 | End-to-end test | Manual verification |
