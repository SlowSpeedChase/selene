# Folio Kindle Agent Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Folio MCP server with 4 tools so a scheduled Claude agent can detect changed documents, write an executive summary + table of contents, and deliver a PDF digest to Kindle.

**Architecture:** Four pure modules in `folio/src/` (delivery log, document scanner, digest PDF generator, MCP server wiring). The MCP server reads `--dir` from CLI args to know which project to scan. Claude is the brain — it calls the tools, reads the docs, writes the summary, and triggers delivery. No new logic in Selene.

**Tech Stack:** TypeScript + `@modelcontextprotocol/sdk` + Puppeteer (existing) + nodemailer (existing) + vitest (existing)

---

## Task 1: Add MCP SDK dependency and delivery log module

**Files:**
- Modify: `~/folio/package.json`
- Create: `~/folio/src/delivery-log.ts`
- Create: `~/folio/tests/delivery-log.test.ts`
- Modify: `~/folio/.gitignore` (add logs entry)

**Step 1: Install the MCP SDK**

```bash
cd ~/folio && npm install @modelcontextprotocol/sdk
```

Expected: `@modelcontextprotocol/sdk` appears in `package.json` dependencies.

**Step 2: Add logs directory to .gitignore**

Add this line to `~/folio/.gitignore`:
```
logs/kindle-deliveries.json
```

**Step 3: Write the failing tests**

Create `~/folio/tests/delivery-log.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { existsSync, unlinkSync, mkdirSync } from 'fs';
import { join } from 'path';
import { readLog, appendDelivery, lastDeliveryTime, type DeliveryRecord } from '../src/delivery-log';

const TMP_LOG = join(__dirname, 'tmp-deliveries.json');

const record: DeliveryRecord = {
  id: '2026-05-26T09:00:00Z',
  sent_at: '2026-05-26T09:00:00Z',
  docs_included: ['CLAUDE.md'],
  doc_count: 1,
  summary_preview: 'One document changed.',
};

beforeEach(() => {
  if (existsSync(TMP_LOG)) unlinkSync(TMP_LOG);
});

afterEach(() => {
  if (existsSync(TMP_LOG)) unlinkSync(TMP_LOG);
});

describe('readLog', () => {
  it('returns empty array when log file does not exist', () => {
    expect(readLog(TMP_LOG)).toEqual([]);
  });

  it('returns parsed entries when log exists', () => {
    appendDelivery(TMP_LOG, record);
    expect(readLog(TMP_LOG)).toHaveLength(1);
    expect(readLog(TMP_LOG)[0].id).toBe('2026-05-26T09:00:00Z');
  });
});

describe('appendDelivery', () => {
  it('creates the file if it does not exist', () => {
    appendDelivery(TMP_LOG, record);
    expect(existsSync(TMP_LOG)).toBe(true);
  });

  it('appends without overwriting existing entries', () => {
    appendDelivery(TMP_LOG, record);
    appendDelivery(TMP_LOG, { ...record, id: '2026-05-27T09:00:00Z', sent_at: '2026-05-27T09:00:00Z' });
    expect(readLog(TMP_LOG)).toHaveLength(2);
  });
});

describe('lastDeliveryTime', () => {
  it('returns null when log is empty', () => {
    expect(lastDeliveryTime(TMP_LOG)).toBeNull();
  });

  it('returns the sent_at of the most recent entry as a Date', () => {
    appendDelivery(TMP_LOG, record);
    appendDelivery(TMP_LOG, { ...record, id: '2026-05-27T09:00:00Z', sent_at: '2026-05-27T09:00:00Z' });
    const t = lastDeliveryTime(TMP_LOG);
    expect(t).not.toBeNull();
    expect(t!.toISOString()).toBe('2026-05-27T09:00:00.000Z');
  });
});
```

**Step 4: Run the tests to verify they fail**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "delivery-log|FAIL|Cannot find"
```

Expected: FAIL — `Cannot find module '../src/delivery-log'`

**Step 5: Implement the delivery log module**

Create `~/folio/src/delivery-log.ts`:

```typescript
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { dirname } from 'path';

export interface DeliveryRecord {
  id: string;
  sent_at: string;
  docs_included: string[];
  doc_count: number;
  summary_preview: string;
}

export function readLog(logPath: string): DeliveryRecord[] {
  if (!existsSync(logPath)) return [];
  return JSON.parse(readFileSync(logPath, 'utf-8')) as DeliveryRecord[];
}

export function appendDelivery(logPath: string, record: DeliveryRecord): void {
  const entries = readLog(logPath);
  entries.push(record);
  mkdirSync(dirname(logPath), { recursive: true });
  writeFileSync(logPath, JSON.stringify(entries, null, 2));
}

export function lastDeliveryTime(logPath: string): Date | null {
  const entries = readLog(logPath);
  if (entries.length === 0) return null;
  return new Date(entries[entries.length - 1].sent_at);
}
```

**Step 6: Run the tests to verify they pass**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "delivery-log|PASS|FAIL"
```

Expected: All 5 delivery-log tests PASS.

**Step 7: Commit**

```bash
cd ~/folio && git add package.json package-lock.json src/delivery-log.ts tests/delivery-log.test.ts .gitignore
git commit -m "feat: add delivery log module + MCP SDK dependency"
```

---

## Task 2: Document scanner

**Files:**
- Create: `~/folio/src/kindle-agent.ts`
- Create: `~/folio/tests/kindle-agent.test.ts`

**Step 1: Write the failing tests**

Create `~/folio/tests/kindle-agent.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('fs');
vi.mock('./render', () => ({
  listFiles: vi.fn(),
}));

import { statSync } from 'fs';
import { listFiles } from '../src/render';
import { listChangedDocuments, readDocument } from '../src/kindle-agent';

const mockStatSync = vi.mocked(statSync);
const mockListFiles = vi.mocked(listFiles);

const OLD = new Date('2026-05-20T00:00:00Z');
const NEW = new Date('2026-05-26T00:00:00Z');
const CUTOFF = new Date('2026-05-24T00:00:00Z');

beforeEach(() => {
  vi.clearAllMocks();
  mockListFiles.mockReturnValue([
    { path: 'CLAUDE.md' },
    { path: 'docs/plans/INDEX.md' },
  ] as any);
});

describe('listChangedDocuments', () => {
  it('returns all documents when since is null (first run)', () => {
    mockStatSync.mockReturnValue({ mtime: OLD, size: 100 } as any);
    const results = listChangedDocuments('/project', null);
    expect(results).toHaveLength(2);
  });

  it('returns only documents newer than the cutoff', () => {
    mockStatSync
      .mockReturnValueOnce({ mtime: NEW, size: 200 } as any)  // CLAUDE.md — new
      .mockReturnValueOnce({ mtime: OLD, size: 100 } as any); // INDEX.md — old
    const results = listChangedDocuments('/project', CUTOFF);
    expect(results).toHaveLength(1);
    expect(results[0].path).toBe('CLAUDE.md');
  });

  it('returns empty array when nothing changed', () => {
    mockStatSync.mockReturnValue({ mtime: OLD, size: 100 } as any);
    const results = listChangedDocuments('/project', CUTOFF);
    expect(results).toHaveLength(0);
  });
});

describe('readDocument', () => {
  it('throws on path traversal attempt', () => {
    expect(() => readDocument('../../etc/passwd', '/project')).toThrow('Path traversal rejected');
  });
});
```

**Step 2: Run the tests to verify they fail**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "kindle-agent|FAIL|Cannot find"
```

Expected: FAIL — `Cannot find module '../src/kindle-agent'`

**Step 3: Implement the document scanner**

Create `~/folio/src/kindle-agent.ts`:

```typescript
import { statSync, readFileSync } from 'fs';
import { resolve, join, sep } from 'path';
import { listFiles } from './render';

export interface ChangedDoc {
  path: string;
  mtime: Date;
  size: number;
}

export function listChangedDocuments(projectDir: string, since: Date | null): ChangedDoc[] {
  const files = listFiles(projectDir);
  return files
    .map(f => {
      const full = resolve(join(projectDir, f.path));
      const stat = statSync(full);
      return { path: f.path, mtime: stat.mtime, size: stat.size };
    })
    .filter(f => since === null || f.mtime > since);
}

export function readDocument(filePath: string, projectDir: string): string {
  const full = resolve(join(projectDir, filePath));
  if (!full.startsWith(resolve(projectDir) + sep)) {
    throw new Error(`Path traversal rejected: ${filePath}`);
  }
  return readFileSync(full, 'utf-8');
}
```

**Step 4: Run the tests to verify they pass**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "kindle-agent|PASS|FAIL"
```

Expected: All 4 kindle-agent tests PASS.

**Step 5: Commit**

```bash
cd ~/folio && git add src/kindle-agent.ts tests/kindle-agent.test.ts
git commit -m "feat: add document scanner with delta detection"
```

---

## Task 3: Digest PDF generator

**Files:**
- Create: `~/folio/src/digest-pdf.ts`
- Create: `~/folio/tests/digest-pdf.test.ts`

**Step 1: Write the failing tests**

Create `~/folio/tests/digest-pdf.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('puppeteer');
vi.mock('fs', async (importOriginal) => {
  const actual = await importOriginal<typeof import('fs')>();
  return { ...actual, readFileSync: vi.fn(() => '/* mock css */') };
});

import puppeteer from 'puppeteer';
import { generateDigestPdf } from '../src/digest-pdf';

const mockBrowser = {
  newPage: vi.fn(),
  close: vi.fn(),
};
const mockPage = {
  setContent: vi.fn(),
  pdf: vi.fn().mockResolvedValue(Buffer.from('%PDF-digest')),
};

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(puppeteer.launch).mockResolvedValue(mockBrowser as any);
  mockBrowser.newPage.mockResolvedValue(mockPage as any);
});

describe('generateDigestPdf', () => {
  it('returns a Buffer', async () => {
    const result = await generateDigestPdf(
      '# Summary\nTwo docs changed.',
      ['CLAUDE.md', 'docs/INDEX.md'],
      [{ path: 'CLAUDE.md', content: '# Title\ncontent' }]
    );
    expect(Buffer.isBuffer(result)).toBe(true);
  });

  it('calls setContent with summary, toc, and doc content', async () => {
    await generateDigestPdf(
      '# Summary',
      ['CLAUDE.md'],
      [{ path: 'CLAUDE.md', content: '# Content' }]
    );
    const html = mockPage.setContent.mock.calls[0][0] as string;
    expect(html).toContain('CLAUDE.md');
  });

  it('closes the browser even if pdf() throws', async () => {
    mockPage.pdf.mockRejectedValueOnce(new Error('PDF failed'));
    await expect(generateDigestPdf('', [], [])).rejects.toThrow('PDF failed');
    expect(mockBrowser.close).toHaveBeenCalled();
  });
});
```

**Step 2: Run the tests to verify they fail**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "digest-pdf|FAIL|Cannot find"
```

Expected: FAIL — `Cannot find module '../src/digest-pdf'`

**Step 3: Implement the digest PDF generator**

Create `~/folio/src/digest-pdf.ts`:

```typescript
import puppeteer from 'puppeteer';
import { readFileSync } from 'fs';
import { join } from 'path';
import { renderMarkdown, escapeHtml } from './render';

const PDF_CSS = readFileSync(join(__dirname, '../templates/pdf.css'), 'utf-8');

export interface DigestDoc {
  path: string;
  content: string;
}

export async function generateDigestPdf(
  executiveSummary: string,
  toc: string[],
  docs: DigestDoc[]
): Promise<Buffer> {
  const summaryHtml = renderMarkdown(executiveSummary);
  const tocHtml = `<ul>${toc.map(item => `<li>${escapeHtml(item)}</li>`).join('')}</ul>`;
  const docsHtml = docs
    .map(d => {
      const body = d.path.endsWith('.md')
        ? renderMarkdown(d.content)
        : `<pre>${escapeHtml(d.content)}</pre>`;
      return `<div class="doc-section"><h2>${escapeHtml(d.path)}</h2>${body}</div>`;
    })
    .join('');

  const html = `<!DOCTYPE html>
<html><head>
  <meta charset="UTF-8">
  <style>
    ${PDF_CSS}
    .doc-section { page-break-before: always; }
  </style>
</head><body>
  <h1>Folio Digest</h1>
  ${summaryHtml}
  <div style="page-break-after:always"></div>
  <h1>Table of Contents</h1>
  ${tocHtml}
  ${docsHtml}
</body></html>`;

  const browser = await puppeteer.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'load' });
    const pdf = await page.pdf({
      format: 'A4',
      margin: { top: '2cm', right: '9cm', bottom: '2cm', left: '1.5cm' },
      printBackground: false,
    });
    return Buffer.from(pdf);
  } finally {
    await browser.close();
  }
}
```

**Step 4: Run the tests to verify they pass**

```bash
cd ~/folio && npm test -- --reporter=verbose 2>&1 | grep -E "digest-pdf|PASS|FAIL"
```

Expected: All 3 digest-pdf tests PASS.

**Step 5: Commit**

```bash
cd ~/folio && git add src/digest-pdf.ts tests/digest-pdf.test.ts
git commit -m "feat: add digest PDF generator (summary + ToC + docs)"
```

---

## Task 4: MCP server

**Files:**
- Create: `~/folio/src/mcp.ts`

No unit tests — this is thin wiring. Validate manually at the end.

**Step 1: Verify TypeScript can resolve the MCP SDK**

```bash
cd ~/folio && node -e "require('@modelcontextprotocol/sdk/server/index.js')" && echo "OK"
```

Expected: `OK` (no error). If it fails, run `npm install` again.

**Step 2: Create the MCP server**

Create `~/folio/src/mcp.ts`:

```typescript
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import minimist from 'minimist';
import { join, resolve } from 'path';
import { listChangedDocuments, readDocument } from './kindle-agent';
import { readLog, appendDelivery, lastDeliveryTime } from './delivery-log';
import { generateDigestPdf } from './digest-pdf';
import { sendToKindle, smtpConfigFromEnv } from './send';

const argv = minimist(process.argv.slice(2));
const projectDir = resolve(
  (argv['dir'] as string | undefined) ??
  process.env.FOLIO_DIR ??
  (process.env.HOME + '/selene')
);
const LOG_PATH = join(__dirname, '../logs/kindle-deliveries.json');

const server = new Server(
  { name: 'folio', version: '0.1.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'list_changed_documents',
      description: 'List documents in the project modified since the last Kindle delivery. Returns path, mtime, and size for each changed file. Returns all documents on first run.',
      inputSchema: { type: 'object' as const, properties: {}, required: [] },
    },
    {
      name: 'read_document',
      description: 'Read the raw content of a document by its path (relative to project root).',
      inputSchema: {
        type: 'object' as const,
        properties: { path: { type: 'string', description: 'Relative path within the project' } },
        required: ['path'],
      },
    },
    {
      name: 'get_delivery_history',
      description: 'Get the last 5 Kindle delivery records (timestamp, docs sent, summary preview).',
      inputSchema: { type: 'object' as const, properties: {}, required: [] },
    },
    {
      name: 'send_kindle_digest',
      description: 'Generate a PDF digest (executive summary + ToC + full docs) and email it to Kindle. Updates the delivery log.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          executive_summary: { type: 'string', description: 'Markdown-formatted executive summary of changes' },
          toc: { type: 'array', items: { type: 'string' }, description: 'List of document paths included' },
          docs: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                content: { type: 'string' },
              },
              required: ['path', 'content'],
            },
          },
        },
        required: ['executive_summary', 'toc', 'docs'],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === 'list_changed_documents') {
    const since = lastDeliveryTime(LOG_PATH);
    const docs = listChangedDocuments(projectDir, since);
    return { content: [{ type: 'text' as const, text: JSON.stringify(docs, null, 2) }] };
  }

  if (name === 'read_document') {
    const { path } = args as { path: string };
    const content = readDocument(path, projectDir);
    return { content: [{ type: 'text' as const, text: content }] };
  }

  if (name === 'get_delivery_history') {
    const entries = readLog(LOG_PATH).slice(-5);
    return { content: [{ type: 'text' as const, text: JSON.stringify(entries, null, 2) }] };
  }

  if (name === 'send_kindle_digest') {
    const { executive_summary, toc, docs } = args as {
      executive_summary: string;
      toc: string[];
      docs: Array<{ path: string; content: string }>;
    };
    const smtp = smtpConfigFromEnv();
    if (!smtp) throw new Error('SMTP not configured — set KINDLE_SMTP_HOST, KINDLE_SMTP_USER, KINDLE_SMTP_PASS');
    const kindleEmail = process.env.KINDLE_EMAIL;
    if (!kindleEmail) throw new Error('KINDLE_EMAIL env var not set');

    const pdf = await generateDigestPdf(executive_summary, toc, docs);
    const filename = `folio-digest-${new Date().toISOString().slice(0, 10)}.pdf`;
    await sendToKindle(pdf, filename, kindleEmail, smtp);

    appendDelivery(LOG_PATH, {
      id: new Date().toISOString(),
      sent_at: new Date().toISOString(),
      docs_included: docs.map(d => d.path),
      doc_count: docs.length,
      summary_preview: executive_summary.slice(0, 200),
    });

    return {
      content: [{ type: 'text' as const, text: `Sent ${docs.length} documents to Kindle as ${filename}` }],
    };
  }

  throw new Error(`Unknown tool: ${name}`);
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
```

**Step 3: Type-check the new file**

```bash
cd ~/folio && npx tsc --noEmit 2>&1
```

Expected: No errors. If errors appear, fix them before continuing.

**Step 4: Smoke-test the MCP server starts**

```bash
cd ~/folio && echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | npx ts-node src/mcp.ts --dir ~/selene 2>&1 | head -5
```

Expected: JSON response containing `"list_changed_documents"`.

**Step 5: Commit**

```bash
cd ~/folio && git add src/mcp.ts
git commit -m "feat: add Folio MCP server with 4 Kindle digest tools"
```

---

## Task 5: MCP registration and scheduled agent

**Files:**
- Modify: `~/selene/.claude/settings.json` (add mcpServers)
- Modify: `~/.claude/settings.json` (add mcpServers globally, if it exists)

**Step 1: Register Folio MCP in Selene's project settings**

Add `mcpServers` to `~/selene/.claude/settings.json`. The file currently has only `hooks`. Add the new key at the top level:

```json
{
  "mcpServers": {
    "folio": {
      "command": "npx",
      "args": ["ts-node", "/Users/chaseeasterling/folio/src/mcp.ts", "--dir", "/Users/chaseeasterling/selene"]
    }
  },
  "hooks": { ... existing hooks ... }
}
```

**Step 2: Verify Claude Code sees the MCP server**

In a Claude Code session in `~/selene`, run:

```
/mcp
```

Expected: `folio` appears in the list of connected MCP servers with 4 tools.

**Step 3: Run a manual end-to-end test**

In a Claude Code session, ask:

> "Use the folio MCP tools to check what documents have changed. If there are any, read them, write a short executive summary and table of contents, and call send_kindle_digest."

Expected: Claude calls `list_changed_documents`, reads docs with `read_document`, writes summary/ToC, and calls `send_kindle_digest`. A PDF arrives on Kindle.

**Step 4: Create the scheduled nightly agent**

Use the `/schedule` skill to create a recurring agent. In a Claude Code session:

```
/schedule
```

When prompted, configure:
- **Name:** `folio-kindle-digest`
- **Schedule:** `0 9 * * *` (9am daily)
- **Prompt:** 
  ```
  You are the Folio Kindle digest agent. Use the folio MCP tools to:
  1. Call list_changed_documents to see what has changed since the last delivery.
  2. If the list is empty, stop — do not send a digest.
  3. For each changed document, call read_document to get its content.
  4. Write a markdown executive summary (2-4 paragraphs) synthesizing the key changes.
  5. Build a table of contents listing each changed document path.
  6. Call send_kindle_digest with your executive_summary, toc array, and docs array.
  Report what you sent or that nothing was sent.
  ```

**Step 5: Commit the settings change**

```bash
cd ~/selene && git add .claude/settings.json
git commit -m "feat: register Folio MCP server in project settings"
```

---

## Acceptance Checklist

- [ ] `npm test` in `~/folio` passes all tests including new ones
- [ ] `npx tsc --noEmit` in `~/folio` reports no errors
- [ ] `/mcp` in Claude Code shows `folio` with 4 tools
- [ ] `list_changed_documents` returns correct delta vs. last delivery
- [ ] `read_document` rejects `../../` paths
- [ ] `send_kindle_digest` emails a PDF to Kindle and updates `kindle-deliveries.json`
- [ ] No digest sent when nothing changed (agent exits early)
- [ ] Nightly cron agent registered and visible in `/schedule` list
