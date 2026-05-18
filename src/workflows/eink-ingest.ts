import { execSync } from 'child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'fs';
import { basename, dirname, join } from 'path';
import { tmpdir } from 'os';
import { createWorkflowLogger } from '../lib';
import { config } from '../lib/config';

const log = createWorkflowLogger('eink-ingest');

// ── Types ─────────────────────────────────────────────────────────────────────

interface ManifestEntry {
  processedAt: string;
  pageCount: number;
  archivedTo: string;
  sentToDrafts: boolean;
  draftsTitle: string;
}

interface Manifest {
  [filename: string]: ManifestEntry;
}

export interface EinkIngestOptions {
  limit?: number;
  dryRun?: boolean;
}

export interface EinkIngestResult {
  discovered: number;
  skipped: number;
  processed: number;
  failed: number;
  details: NotebookResult[];
}

export interface NotebookResult {
  filename: string;
  success: boolean;
  pageCount?: number;
  archivePath?: string;
  error?: string;
}

export class EinkIngestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EinkIngestError';
  }
}

// ── OCR prompt ────────────────────────────────────────────────────────────────

const OCR_PROMPT = `Transcribe all handwritten text from this image exactly as written.
Preserve line breaks and structure (lists, headers, indentation).
If a word is not clearly legible, write [?] — do NOT guess from context. Inserting a wrong word is worse than marking it unclear.
If you see a hand-drawn diagram, flowchart, or visual structure (arrows, boxes, mind maps), write [DIAGRAM: brief description of what you see] on its own line instead of trying to transcribe it.
Do not add commentary or interpretation — just the raw transcription.`;

// ── Main entry ────────────────────────────────────────────────────────────────

export async function einkIngest(options: EinkIngestOptions = {}): Promise<EinkIngestResult> {
  const stats: EinkIngestResult = { discovered: 0, skipped: 0, processed: 0, failed: 0, details: [] };

  ensureDirectories();

  const pdfs = scanForNewFiles(options.limit);
  stats.discovered = pdfs.length;
  log.info({ discovered: pdfs.length }, 'Discovered notebooks');

  for (const pdfPath of pdfs) {
    const result = await processNotebook(pdfPath, options.dryRun ?? false);
    stats.details.push(result);
    if (result.success) {
      stats.processed++;
    } else {
      stats.failed++;
    }
  }

  log.info(
    { discovered: stats.discovered, skipped: stats.skipped, processed: stats.processed, failed: stats.failed },
    'E-ink ingest run complete'
  );
  return stats;
}

// ── Scanning ──────────────────────────────────────────────────────────────────

function scanForNewFiles(limit?: number): string[] {
  const watchDir = config.einkWatchDir;
  if (!existsSync(watchDir)) {
    log.warn({ watchDir }, 'Watch directory does not exist — nothing to process');
    return [];
  }

  const manifest = loadManifest();
  const now = Date.now();
  const SETTLE_MS = 10_000; // skip files modified in last 10s (mid-iCloud-sync)

  const pdfs = readdirSync(watchDir)
    .filter(f => f.toLowerCase().endsWith('.pdf'))
    .filter(f => !manifest[f])
    .filter(f => {
      const mtime = statSync(join(watchDir, f)).mtimeMs;
      return now - mtime > SETTLE_MS;
    })
    .sort()
    .map(f => join(watchDir, f));

  return limit !== undefined ? pdfs.slice(0, limit) : pdfs;
}

// ── Per-notebook pipeline ─────────────────────────────────────────────────────

async function processNotebook(pdfPath: string, dryRun: boolean): Promise<NotebookResult> {
  const filename = basename(pdfPath);
  const result: NotebookResult = { filename, success: false };

  log.info({ filename }, 'Processing notebook');

  const tmpDir = mkdtempSync(join(tmpdir(), 'selene-eink-'));
  try {
    // 1. Convert all pages to PNG
    let imagePaths: string[];
    try {
      imagePaths = convertPdfToImages(pdfPath, tmpDir);
    } catch (err) {
      result.error = `PDF conversion failed: ${(err as Error).message}`;
      log.error({ filename, err: result.error }, 'PDF conversion failed');
      return result;
    }

    result.pageCount = imagePaths.length;
    log.info({ filename, pages: imagePaths.length }, 'Converted PDF to images');

    // 2. OCR each page
    const pageTexts: string[] = [];
    for (let i = 0; i < imagePaths.length; i++) {
      try {
        const text = await recognizePage(imagePaths[i]);
        pageTexts.push(text);
        log.info({ filename, page: i + 1, chars: text.length }, 'Page OCR complete');
      } catch (err) {
        const msg = `Page ${i + 1} OCR failed: ${(err as Error).message}`;
        log.warn({ filename, page: i + 1, err: msg }, 'Page OCR failed — inserting placeholder');
        pageTexts.push(`[OCR failed for page ${i + 1}]`);
      }
    }

    // 3. Combine pages
    const noteTitle = buildTitle(filename);
    const noteBody = combinePages(noteTitle, pageTexts);

    if (dryRun) {
      log.info({ filename, chars: noteBody.length }, 'Dry run — skipping Drafts send and archive');
      result.success = true;
      return result;
    }

    // 4. Send to Drafts for human review
    try {
      sendToDrafts(noteTitle, noteBody);
      log.info({ filename, title: noteTitle }, 'Sent to Drafts for review');
    } catch (err) {
      result.error = `Drafts send failed: ${(err as Error).message}`;
      log.error({ filename, err: result.error }, 'Drafts send failed');
      return result;
    }

    // 5. Archive PDF
    let archivePath: string;
    try {
      archivePath = archivePdf(pdfPath);
      result.archivePath = archivePath;
    } catch (err) {
      result.error = `Archive failed: ${(err as Error).message}`;
      log.error({ filename, err: result.error }, 'Archive failed');
      return result;
    }

    // 6. Update manifest
    updateManifest(filename, {
      processedAt: new Date().toISOString(),
      pageCount: imagePaths.length,
      archivedTo: archivePath,
      sentToDrafts: true,
      draftsTitle: noteTitle,
    });

    result.success = true;
    return result;
  } finally {
    // Always clean up temp page images
    try {
      rmSync(tmpDir, { recursive: true, force: true });
    } catch {
      // best-effort
    }
  }
}

// ── PDF → images ──────────────────────────────────────────────────────────────

function convertPdfToImages(pdfPath: string, outDir: string): string[] {
  const prefix = join(outDir, 'page');
  // -r 150: 150 DPI — good balance of OCR quality vs file size
  execSync(`pdftoppm -r 150 -png "${pdfPath}" "${prefix}"`, { stdio: 'pipe' });

  const images = readdirSync(outDir)
    .filter(f => f.startsWith('page') && f.endsWith('.png'))
    .sort()
    .map(f => join(outDir, f));

  if (images.length === 0) {
    throw new Error(`pdftoppm produced no PNG files for ${basename(pdfPath)}`);
  }
  return images;
}

// ── OCR ───────────────────────────────────────────────────────────────────────

async function recognizePage(imagePath: string): Promise<string> {
  const imageData = readFileSync(imagePath).toString('base64');

  const res = await fetch(`${config.ollamaUrl}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: config.einkVisionModel,
      prompt: OCR_PROMPT,
      images: [imageData],
      stream: false,
      options: { temperature: 0 },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Ollama error ${res.status}: ${err}`);
  }

  const data = await res.json() as { response: string };
  return data.response.trim();
}

// ── Formatting ────────────────────────────────────────────────────────────────

function buildTitle(filename: string): string {
  // "2026-05-17_kindle_journal.pdf" → "E-Ink: 2026-05-17 kindle journal"
  const stem = basename(filename, '.pdf').replace(/_/g, ' ');
  return `E-Ink: ${stem}`;
}

function combinePages(title: string, pageTexts: string[]): string {
  const pages = pageTexts
    .map((text, i) => `--- Page ${i + 1} ---\n${text}`)
    .join('\n\n');
  return `# ${title}\n\n${pages}\n\n#eink #selene`;
}

// ── Drafts ────────────────────────────────────────────────────────────────────

function sendToDrafts(title: string, content: string): void {
  const url = `drafts://create?title=${encodeURIComponent(title)}&content=${encodeURIComponent(content)}&tags=eink`;
  execSync(`open "${url}"`, { stdio: 'pipe' });
}

// ── Archive ───────────────────────────────────────────────────────────────────

function archivePdf(pdfPath: string): string {
  const archiveDir = config.einkArchiveDir;
  mkdirSync(archiveDir, { recursive: true });

  const filename = basename(pdfPath);
  let target = join(archiveDir, filename);

  // Avoid overwriting if already archived under the same name
  if (existsSync(target)) {
    const stem = filename.replace(/\.pdf$/i, '');
    target = join(archiveDir, `${stem}__${Date.now()}.pdf`);
  }

  try {
    renameSync(pdfPath, target);
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === 'EXDEV') {
      // Cross-device move (iCloud → local)
      const { copyFileSync, unlinkSync } = require('fs') as typeof import('fs');
      copyFileSync(pdfPath, target);
      unlinkSync(pdfPath);
    } else {
      throw new Error(`Failed to move ${filename} → ${target}: ${e.message}`);
    }
  }

  log.info({ from: filename, to: target }, 'Archived PDF');
  return target;
}

// ── Manifest ──────────────────────────────────────────────────────────────────

function loadManifest(): Manifest {
  const path = config.einkManifestPath;
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as Manifest;
  } catch {
    log.warn({ path }, 'Manifest unreadable — starting fresh');
    return {};
  }
}

function updateManifest(filename: string, entry: ManifestEntry): void {
  const path = config.einkManifestPath;
  mkdirSync(join(path, '..'), { recursive: true });
  const manifest = loadManifest();
  manifest[filename] = entry;
  writeFileSync(path, JSON.stringify(manifest, null, 2), 'utf8');
}

function ensureDirectories(): void {
  mkdirSync(config.einkArchiveDir, { recursive: true });
  mkdirSync(config.einkTempDir, { recursive: true });
  mkdirSync(dirname(config.einkManifestPath), { recursive: true });
}

// ── CLI entry ─────────────────────────────────────────────────────────────────

if (require.main === module) {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const limitArg = args.find(a => /^\d+$/.test(a));
  const limit = limitArg ? parseInt(limitArg, 10) : undefined;

  einkIngest({ limit, dryRun })
    .then(result => {
      console.log('E-ink ingest complete:', {
        discovered: result.discovered,
        skipped: result.skipped,
        processed: result.processed,
        failed: result.failed,
      });
      process.exit(result.failed > 0 ? 1 : 0);
    })
    .catch(err => {
      console.error('E-ink ingest failed:', err);
      process.exit(1);
    });
}
