import { logger } from '../lib/logger';
import {
  runAgentMigrations,
  upsertAgent,
  createJob,
  updateJobStatus,
  insertActions,
  insertReport,
  touchAgentLastRun,
  AgentActionTargetType,
} from '../lib/agent-db';

export interface ProposedAction {
  action_type: string;
  target_id: string;
  target_type: AgentActionTargetType;
  payload: Record<string, unknown>;
  rationale: string;
  confidence: number;
}

export abstract class BaseAgent {
  abstract name: string;
  abstract allowedActionTypes: string[];

  protected log = logger.child({ module: 'agent' });

  abstract collect(): Promise<unknown>;
  abstract reason(data: unknown): Promise<ProposedAction[]>;

  register(opts: { description: string; schedule?: string; config?: Record<string, unknown> }): void {
    runAgentMigrations();
    upsertAgent({
      agent_name: this.name,
      description: opts.description,
      schedule: opts.schedule,
      allowed_action_types: this.allowedActionTypes,
      config: opts.config,
    });
  }

  validateActionTypes(actions: ProposedAction[]): boolean {
    return actions.every((a) => this.allowedActionTypes.includes(a.action_type));
  }

  async run(): Promise<{ jobId: string; actionCount: number }> {
    this.log.info({ agent: this.name }, 'Agent run started');
    touchAgentLastRun(this.name);

    const jobId = createJob(this.name);

    try {
      const data = await this.collect();
      this.log.info({ agent: this.name, jobId }, 'Data collected');

      const rawActions = await this.reason(data);
      this.log.info({ agent: this.name, jobId, actionCount: rawActions.length }, 'Reasoning complete');

      const validActions = rawActions.filter((a) => this.allowedActionTypes.includes(a.action_type));
      const invalidCount = rawActions.length - validActions.length;
      if (invalidCount > 0) {
        this.log.warn({ agent: this.name, jobId, invalidCount }, 'Filtered out actions with disallowed types');
      }

      if (validActions.length === 0) {
        updateJobStatus(jobId, 'complete', 'No actions proposed');
        return { jobId, actionCount: 0 };
      }

      insertActions(validActions.map((a) => ({ ...a, job_id: jobId })));

      const report = this.buildReport(jobId, validActions, data);
      insertReport({ job_id: jobId, title: report.title, body: report.body });

      updateJobStatus(jobId, 'paused', `Awaiting approval for ${validActions.length} action(s)`);
      this.log.info({ agent: this.name, jobId, actionCount: validActions.length }, 'Agent paused, awaiting approval');

      return { jobId, actionCount: validActions.length };
    } catch (err) {
      const error = err as Error;
      this.log.error({ agent: this.name, jobId, err: error.message }, 'Agent run failed');
      updateJobStatus(jobId, 'error', error.message);
      throw err;
    }
  }

  buildReport(jobId: string, actions: ProposedAction[], _data: unknown): { title: string; body: string } {
    const lines = actions.map(
      (a) => `- **${a.action_type}** on \`${a.target_id}\` (confidence: ${(a.confidence * 100).toFixed(0)}%)\n  > ${a.rationale}`
    );

    return {
      title: `${this.name} — ${actions.length} proposed action(s)`,
      body: `## ${this.name} Report\n\n**Job:** ${jobId}\n\n### Proposed Actions\n\n${lines.join('\n\n')}`,
    };
  }
}
