// @map purpose: OCR handwritten Kindle Scribe PDFs (Ollama vision) and ingest each as a note
// @map reads: eink watch directory (PDFs)
// @map writes: raw_notes (via ingest), eink archive + manifest
import { execSync } from 'child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'fs';
import { basename, dirname, join } from 'path';
import { tmpdir } from 'os';
import { createWorkflowLogger } from '../lib';
import { config } from '../lib/config';
import { ingest } from './ingest';

const log = createWorkflowLogger('eink-ingest');

// ── Types ─────────────────────────────────────────────────────────────────────

interface ManifestEntry {
  processedAt: string;
  pageCount: number;
  archivedTo: string;
  noteId: number;
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

// ── Folio metadata ─────────────────────────────────────────────────────────────

export function parseFolioMetadata(
  filename: string
): { projectDir: string; filePath: string } | null {
  if (!filename.startsWith('folio__')) return null;
  const parts = filename.split('__');
  if (parts.length < 4) return null;
  const projectDir = Buffer.from(parts[1], 'base64url').toString('utf-8');
  const filePath = Buffer.from(parts[2], 'base64url').toString('utf-8');
  if (!projectDir || !filePath) return null;
  return { projectDir, filePath };
}

// ── OCR prompt ────────────────────────────────────────────────────────────────

const OCR_PROMPT = `You are transcribing handwritten annotations from a Kindle Scribe PDF page. The image shows a document page that may have both printed text and handwritten marks added with a stylus.

Your job: extract ONLY the handwritten annotations, not the printed document text.

For each annotation:
- Handwritten words or sentences: transcribe exactly as written, preserving line breaks.
- Circled text (a circle drawn around printed words): write [CIRCLE: the words inside the circle]
- Underlined text (a line drawn under printed words): write [UNDERLINE: the underlined words]
- Arrow: write [ARROW: from X to Y] if the source and target are clear, otherwise [ARROW]
- Hand-drawn diagram, box, or flowchart: write [DIAGRAM: brief description]
- Illegible handwriting: write [?] — do NOT guess from context.

If there are no handwritten annotations on this page, respond with exactly: [NO ANNOTATIONS]

Output the transcription only. No preamble, no commentary, no explanation.`;

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
    const folioMeta = parseFolioMetadata(filename);
    const pageTexts: string[] = [];
    for (let i = 0; i < imagePaths.length; i++) {
      try {
        const processedPath = preprocessImage(imagePaths[i]);
        const text = await recognizePage(processedPath);
        pageTexts.push(text);
        log.info({ filename, page: i + 1, chars: text.length }, 'Page OCR complete');
      } catch (err) {
        const msg = `Page ${i + 1} OCR failed: ${(err as Error).message}`;
        log.warn({ filename, page: i + 1, err: msg }, 'Page OCR failed — inserting placeholder');
        pageTexts.push(`[OCR failed for page ${i + 1}]`);
      }
    }

    // 3. Combine pages
    const noteTitle = folioMeta
      ? `Folio: ${folioMeta.projectDir} :: ${folioMeta.filePath}`
      : buildTitle(filename);
    const noteBody = combinePages(noteTitle, pageTexts);

    if (dryRun) {
      log.info({ filename, chars: noteBody.length }, 'Dry run — skipping ingest and archive');
      result.success = true;
      return result;
    }

    // 4. Ingest directly into Selene
    let noteId: number;
    try {
      const ingestResult = await ingest({
        title: noteTitle,
        content: noteBody,
        created_at: parseDateFromFilename(filename),
        capture_type: folioMeta ? 'folio' : 'eink',
      });
      noteId = ingestResult.id ?? ingestResult.existingId ?? 0;
      log.info({ filename, noteId, duplicate: ingestResult.duplicate }, 'Ingested into Selene');
    } catch (err) {
      result.error = `Ingest failed: ${(err as Error).message}`;
      log.error({ filename, err: result.error }, 'Ingest failed');
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
      noteId,
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
  execSync(`pdftoppm -r 300 -png "${pdfPath}" "${prefix}"`, { stdio: 'pipe' });

  const images = readdirSync(outDir)
    .filter(f => f.startsWith('page') && f.endsWith('.png'))
    .sort()
    .map(f => join(outDir, f));

  if (images.length === 0) {
    throw new Error(`pdftoppm produced no PNG files for ${basename(pdfPath)}`);
  }
  return images;
}

// ── Image preprocessing ───────────────────────────────────────────────────────

function preprocessImage(imagePath: string): string {
  const outPath = imagePath.replace('.png', '-pp.png');
  try {
    execSync(`convert "${imagePath}" -deskew 40% -normalize "${outPath}"`, { stdio: 'pipe' });
    return outPath;
  } catch {
    log.warn({ imagePath }, 'ImageMagick preprocessing failed — using original');
    return imagePath;
  }
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

function parseDateFromFilename(filename: string): string {
  const stem = basename(filename, '.pdf');
  // Handles "2026-05-17_kindle_journal" and "2024-04-21T22:19:36-05:00"
  const match = stem.match(/^(\d{4}-\d{2}-\d{2}(T[\d:+\-Z]+)?)/);
  if (match) {
    const d = new Date(match[1]);
    if (!isNaN(d.getTime())) return d.toISOString();
  }
  // Fallback: time of processing
  return new Date().toISOString();
}

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
