// @map purpose: Run background agents, deliver their pending reports, and escalate stale approvals
// @map reads: agent_jobs, agent_reports
// @map writes: agent_reports (delivery state), Apple Notes, Obsidian vault
import { createWorkflowLogger } from '../lib/logger';
import {
  runAgentMigrations,
  getPausedJobs,
  getAllReports,
  markReportDelivered,
  getReportByJobId,
  getJob,
} from '../lib/agent-db';
import { ThingsMetadataEnricher } from '../agents/things-metadata-enricher';
import { execSync } from 'child_process';
import { upsertAppleNote } from '../lib/apple-notes';

const log = createWorkflowLogger('agent-manager');

const ESCALATION_THRESHOLD_MS = 4 * 60 * 60 * 1000; // 4 hours

function sendMacOSNotification(title: string, body: string): void {
  try {
    const escaped = body.replace(/"/g, '\\"');
    execSync(`osascript -e 'display notification "${escaped}" with title "${title}"'`, { timeout: 5000 });
  } catch (err) {
    log.warn({ err }, 'macOS notification failed');
  }
}

async function deliverToAppleNotes(report: { id: string; title: string; body: string }): Promise<void> {
  const noteName = `Selene Agent: ${report.title.split(' — ')[0]}`;
  upsertAppleNote(noteName, report.body, { mode: 'append' });
}

async function deliverToObsidian(report: {
  id: string;
  title: string;
  body: string;
  created_at: string;
  job_id: string;
}): Promise<void> {
  const { config } = await import('../lib/config');
  const { writeFileSync, mkdirSync } = await import('fs');
  const { join } = await import('path');

  const dir = join(config.vaultPath, 'agent-reports');
  mkdirSync(dir, { recursive: true });

  // Use job's agent_name for filename — job_id is job-<timestamp>-<random>
  const job = getJob(report.job_id);
  const agentName = job?.agent_name ?? 'unknown-agent';
  const date = report.created_at.split('T')[0];
  const filename = `${date}-${agentName}.md`;

  writeFileSync(join(dir, filename), report.body, 'utf-8');
}

async function deliverPendingReports(): Promise<void> {
  const reports = getAllReports(20);

  for (const report of reports) {
    const delivered: string[] = JSON.parse(report.delivered_to);

    if (!delivered.includes('apple-notes')) {
      try {
        await deliverToAppleNotes(report);
        markReportDelivered(report.id, 'apple-notes');
        log.info({ reportId: report.id }, 'Delivered to Apple Notes');
      } catch (err) {
        log.error({ err, reportId: report.id }, 'Apple Notes delivery failed');
      }
    }

    if (!delivered.includes('obsidian')) {
      try {
        await deliverToObsidian(report);
        markReportDelivered(report.id, 'obsidian');
        log.info({ reportId: report.id }, 'Delivered to Obsidian');
      } catch (err) {
        log.error({ err, reportId: report.id }, 'Obsidian delivery failed');
      }
    }
  }
}

async function checkEscalations(): Promise<void> {
  const pausedJobs = getPausedJobs();
  const now = Date.now();

  for (const job of pausedJobs) {
    const pausedMs = now - new Date(job.started_at).getTime();
    if (pausedMs > ESCALATION_THRESHOLD_MS) {
      const report = getReportByJobId(job.id);
      if (report) {
        const delivered: string[] = JSON.parse(report.delivered_to);
        if (!delivered.includes('escalated')) {
          sendMacOSNotification(
            'Selene: Approval Needed',
            `${job.agent_name} has been waiting ${Math.round(pausedMs / 3600000)}h for your review.`
          );
          markReportDelivered(report.id, 'escalated');
          log.info({ jobId: job.id, agent: job.agent_name }, 'Escalation notification sent');
        }
      }
    }
  }
}

function registerKnownAgents(): void {
  const projectName = process.env.THINGS_ENRICHER_PROJECT || 'Inbox';
  const agent = new ThingsMetadataEnricher(projectName);
  agent.register({
    description: 'Enriches Things tasks with metadata (tags, notes) by cross-referencing the Selene note archive',
    schedule: '0 */4 * * *',
    config: { projectName },
  });

  log.info({ projectName }, 'Registered things-metadata-enricher');
}

async function main(): Promise<void> {
  log.info('Agent manager starting');

  runAgentMigrations();
  registerKnownAgents();

  await deliverPendingReports();
  await checkEscalations();

  log.info('Agent manager run complete');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    log.error({ err }, 'Agent manager failed');
    process.exit(1);
  });
