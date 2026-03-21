import { readFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import puppeteer from 'puppeteer';
import { createWorkflowLogger, db, config, getActiveThreads } from '../lib';
import type { Thread } from '../lib/db';

const log = createWorkflowLogger('render-daily-sheet');

function generateQrPlaceholder(date: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
    <rect width="48" height="48" fill="white" stroke="#ccc" stroke-width="1" rx="4"/>
    <text x="24" y="20" text-anchor="middle" font-family="monospace" font-size="6" fill="#333">SELENE</text>
    <text x="24" y="32" text-anchor="middle" font-family="monospace" font-size="7" font-weight="bold" fill="#1a1a1a">${date}</text>
  </svg>`;
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
}

function getMomentumIndicator(score: number | null): { symbol: string; cssClass: string } {
  if (score === null || score === undefined) return { symbol: '\u25CF', cssClass: 'stable' };
  if (score >= 0.6) return { symbol: '\u25B2', cssClass: 'rising' };
  if (score >= 0.3) return { symbol: '\u25CF', cssClass: 'stable' };
  return { symbol: '\u25BC', cssClass: 'cooling' };
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

function formatRelativeTime(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  if (diffHours < 1) return 'just now';
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffHours < 48) return 'yesterday';
  return `${Math.floor(diffHours / 24)}d ago`;
}

interface DailySheetData {
  date: string;
  tasks: Array<{ title: string }>;
  threads: Array<{ name: string; why: string | null; note_count: number; last_activity_at: string | null; momentum_score: number | null }>;
  captures: Array<{ title: string; content: string; created_at: string; essence: string | null }>;
}

function gatherData(): DailySheetData {
  const today = new Date();
  const dateStr = today.toISOString().split('T')[0];

  // Active tasks (not completed) — uses task_metadata table
  let tasks: Array<{ title: string }> = [];
  try {
    tasks = db
      .prepare(
        `SELECT rn.title
         FROM task_metadata tm
         JOIN raw_notes rn ON tm.raw_note_id = rn.id
         WHERE tm.completed_at IS NULL
           AND rn.test_run IS NULL
         ORDER BY tm.id DESC
         LIMIT 12`
      )
      .all() as Array<{ title: string }>;
  } catch (err) {
    // task_metadata table may not exist yet (migration pending)
    log.warn('task_metadata table not available, skipping tasks');
  }

  // Active threads with momentum
  const threads = getActiveThreads(8);

  // Last 8 notes — use essence for display (especially voice memos with useless titles)
  const captures = db
    .prepare(
      `SELECT rn.title, rn.content, rn.created_at, pn.essence
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.test_run IS NULL
       ORDER BY rn.created_at DESC
       LIMIT 8`
    )
    .all() as Array<{ title: string; content: string; created_at: string; essence: string | null }>;

  return {
    date: dateStr,
    tasks: tasks.map((t) => ({ title: t.title })),
    threads: threads.map((t: Thread) => ({
      name: t.name,
      why: t.why,
      note_count: t.note_count,
      last_activity_at: t.last_activity_at,
      momentum_score: t.momentum_score,
    })),
    captures: captures.map((n) => ({
      title: n.title,
      content: n.content,
      created_at: n.created_at,
      essence: n.essence,
    })),
  };
}

function renderHtml(data: DailySheetData): string {
  const templatePath = join(config.projectRoot, 'src', 'templates', 'daily-sheet.html');
  let html = readFileSync(templatePath, 'utf-8');

  html = html.replace('{{DATE}}', data.date);
  html = html.replace('{{QR_DATA_URI}}', generateQrPlaceholder(data.date));

  const tasksHtml = data.tasks.length > 0
    ? data.tasks.map((t) => `<li>${escapeHtml(t.title)}</li>`).join('\n      ')
    : '<li style="color: #999; list-style: none;">No active tasks</li>';
  html = html.replace('{{TASKS}}', tasksHtml);

  const threadsHtml = data.threads.length > 0
    ? data.threads.map((t) => {
        const m = getMomentumIndicator(t.momentum_score);
        const status = t.why
          ? ` — <span class="thread-summary">${escapeHtml(t.why.slice(0, 60))}</span>`
          : '';
        const meta = ` <span class="capture-time">${t.note_count} notes · ${t.last_activity_at ? formatRelativeTime(t.last_activity_at) : 'no activity'}</span>`;
        return `<li><span class="momentum ${m.cssClass}">${m.symbol}</span> <span class="thread-name">${escapeHtml(t.name)}</span>${status}${meta}</li>`;
      }).join('\n      ')
    : '<li style="color: #999;">No active threads</li>';
  html = html.replace('{{THREADS}}', threadsHtml);

  const capturesHtml = data.captures.length > 0
    ? data.captures.map((c) => {
        const isVoiceMemo = c.title.startsWith('Voice Memo');
        const displayText = c.essence
          ? c.essence.slice(0, 90)
          : isVoiceMemo
            ? c.content.slice(0, 90)
            : c.title;
        return `<li>${escapeHtml(displayText)} <span class="capture-time">${formatRelativeTime(c.created_at)}</span></li>`;
      }).join('\n      ')
    : '<li style="color: #999;">No notes yet</li>';
  html = html.replace('{{CAPTURES}}', capturesHtml);

  return html;
}

export async function renderDailySheet(): Promise<{ success: boolean; path?: string }> {
  log.info('Starting daily sheet render');

  try {
    const data = gatherData();
    log.info(
      { tasks: data.tasks.length, threads: data.threads.length, captures: data.captures.length },
      'Data gathered'
    );

    const html = renderHtml(data);

    const outputDir = join(config.digestsPath, 'daily-sheets');
    if (!existsSync(outputDir)) {
      mkdirSync(outputDir, { recursive: true });
    }

    const pdfPath = join(outputDir, `selene-daily-${data.date}.pdf`);

    const browser = await puppeteer.launch({ headless: true });
    try {
      const page = await browser.newPage();
      await page.setContent(html, { waitUntil: 'networkidle0' });
      await page.pdf({
        path: pdfPath,
        format: 'Letter',
        printBackground: true,
        margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
      });
    } finally {
      await browser.close();
    }

    log.info({ pdfPath }, 'Daily sheet rendered');

    if (process.env.SELENE_AUTO_PRINT === 'true') {
      const { execSync } = await import('child_process');
      try {
        execSync(`lp "${pdfPath}"`);
        log.info({ pdfPath }, 'Daily sheet sent to printer');
      } catch (err) {
        log.warn({ err }, 'Auto-print failed (non-fatal)');
      }
    }

    return { success: true, path: pdfPath };
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to render daily sheet');
    return { success: false };
  }
}

if (require.main === module) {
  renderDailySheet()
    .then((result) => {
      console.log('Daily sheet render:', result);
      process.exit(result.success ? 0 : 1);
    })
    .catch((err) => {
      console.error('Daily sheet render failed:', err);
      process.exit(1);
    });
}
