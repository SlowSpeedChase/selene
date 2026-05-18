#!/usr/bin/env npx ts-node
/**
 * Quick viability test for handwriting OCR on Kindle Scribe PDFs.
 *
 * Usage:
 *   npx ts-node scripts/test-eink-ocr.ts
 *   npx ts-node scripts/test-eink-ocr.ts --model richardyoung/olmocr2
 *   npx ts-node scripts/test-eink-ocr.ts --samples 5
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ── Config ────────────────────────────────────────────────────────────────────

const ICLOUD_NOTEBOOKS = path.join(
  os.homedir(),
  'Library/Mobile Documents/com~apple~CloudDocs/Documents/iCloud Kindle Notebooks'
);

const OLLAMA_URL = 'http://127.0.0.1:11434';

// Parse args
const args = process.argv.slice(2);
const modelFlag = args.indexOf('--model');
const samplesFlag = args.indexOf('--samples');

const MODEL = modelFlag >= 0 ? args[modelFlag + 1] : 'granite3.2-vision:2b';
const SAMPLE_COUNT = samplesFlag >= 0 ? parseInt(args[samplesFlag + 1], 10) : 3;

const OCR_PROMPT = `Transcribe all handwritten text from this image exactly as written.
Preserve line breaks and structure (lists, headers, indentation).
If a word is not clearly legible, write [?] — do NOT guess from context. Inserting a wrong word is worse than marking it unclear.
If you see a hand-drawn diagram, flowchart, or visual structure (arrows, boxes, mind maps), write [DIAGRAM: brief description of what you see] on its own line instead of trying to transcribe it.
Do not add commentary or interpretation — just the raw transcription.`;

// ── Helpers ───────────────────────────────────────────────────────────────────

function pickSamples(dir: string, count: number): string[] {
  const files = fs.readdirSync(dir)
    .filter(f => f.endsWith('.pdf'))
    .sort();
  // Spread across the range: beginning, middle, recent
  const indices = Array.from({ length: count }, (_, i) =>
    Math.round(i * (files.length - 1) / (count - 1))
  );
  return [...new Set(indices)].map(i => path.join(dir, files[i]));
}

function extractFirstPage(pdfPath: string, outDir: string): string {
  const base = path.basename(pdfPath, '.pdf');
  const prefix = path.join(outDir, base);
  execSync(`pdftoppm -r 150 -png -f 1 -l 1 "${pdfPath}" "${prefix}"`, { stdio: 'pipe' });
  // pdftoppm outputs prefix-1.png or prefix-01.png
  const candidates = fs.readdirSync(outDir)
    .filter(f => f.startsWith(path.basename(prefix)) && f.endsWith('.png'))
    .map(f => path.join(outDir, f));
  if (candidates.length === 0) throw new Error(`No PNG produced for ${pdfPath}`);
  return candidates[0];
}

async function ocrPage(imagePath: string): Promise<string> {
  const imageData = fs.readFileSync(imagePath).toString('base64');

  const res = await fetch(`${OLLAMA_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: MODEL,
      prompt: OCR_PROMPT,
      images: [imageData],
      stream: false,
      options: { temperature: 0 },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Ollama error: ${res.status} ${err}`);
  }

  const data = await res.json() as { response: string; total_duration?: number };
  const secs = data.total_duration ? (data.total_duration / 1e9).toFixed(1) : '?';
  process.stdout.write(`  (${secs}s inference)\n`);
  return data.response.trim();
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n=== Kindle Scribe OCR Test ===`);
  console.log(`Model: ${MODEL}`);
  console.log(`Samples: ${SAMPLE_COUNT}`);
  console.log(`Source: ${ICLOUD_NOTEBOOKS}\n`);

  // Verify Ollama is up
  try {
    const ping = await fetch(`${OLLAMA_URL}/api/tags`);
    if (!ping.ok) throw new Error('not ok');
  } catch {
    console.error('ERROR: Ollama is not running. Start it with: ollama serve');
    process.exit(1);
  }

  const samples = pickSamples(ICLOUD_NOTEBOOKS, SAMPLE_COUNT);
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'selene-ocr-'));

  try {
    for (let i = 0; i < samples.length; i++) {
      const pdf = samples[i];
      const label = path.basename(pdf);
      console.log(`\n${'─'.repeat(60)}`);
      console.log(`[${i + 1}/${samples.length}] ${label}`);
      console.log(`${'─'.repeat(60)}`);

      process.stdout.write('Converting page 1 to PNG...');
      let imagePath: string;
      try {
        imagePath = extractFirstPage(pdf, tmpDir);
        console.log(` done (${path.basename(imagePath)})`);
      } catch (e) {
        console.log(` FAILED: ${e}`);
        continue;
      }

      process.stdout.write('Running OCR...\n');
      let text: string;
      try {
        text = await ocrPage(imagePath);
      } catch (e) {
        console.log(`OCR FAILED: ${e}`);
        continue;
      }

      const diagramCount = (text.match(/\[DIAGRAM/g) || []).length;
      const unclearCount = (text.match(/\[\?]/g) || []).length;

      console.log('\n--- OCR Output ---');
      console.log(text);
      console.log('\n--- Stats ---');
      console.log(`  Characters: ${text.length}`);
      console.log(`  [DIAGRAM] flags: ${diagramCount}`);
      console.log(`  [?] unclear words: ${unclearCount}`);

      // Clean up this file's PNG to save space
      fs.unlinkSync(imagePath);
    }
  } finally {
    try { fs.rmdirSync(tmpDir); } catch { /* ignore if not empty */ }
  }

  console.log(`\n${'═'.repeat(60)}`);
  console.log('Test complete. Evaluate output quality above.');
  console.log('To test a better model:');
  console.log('  ollama pull richardyoung/olmocr2');
  console.log('  npx ts-node scripts/test-eink-ocr.ts --model richardyoung/olmocr2');
}

main().catch(e => { console.error(e); process.exit(1); });
