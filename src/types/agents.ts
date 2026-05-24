// Agent layer types — re-exported from the canonical source in lib/agent-db.
// Import from here for clean module boundaries; the source of truth stays in agent-db.ts.
export type {
  AgentJobStatus,
  AgentActionStatus,
  AgentActionTargetType,
  AgentRegistryRow,
  AgentJobRow,
  AgentActionRow,
  AgentReportRow,
} from '../lib/agent-db';

export type { ProposedAction } from '../agents/base-agent';
