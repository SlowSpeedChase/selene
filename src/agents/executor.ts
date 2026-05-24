import { logger } from '../lib/logger';
import { updateActionStatus, AgentActionRow } from '../lib/agent-db';
import { updateTaskNotes, addTagToTask } from '../lib/things';

type ActionHandler = (action: AgentActionRow) => Promise<void>;

export class ActionExecutor {
  private handlers = new Map<string, ActionHandler>();
  private log = logger.child({ module: 'executor' });

  register(actionType: string, handler: ActionHandler): void {
    this.handlers.set(actionType, handler);
  }

  hasHandler(actionType: string): boolean {
    return this.handlers.has(actionType);
  }

  async execute(action: AgentActionRow): Promise<void> {
    const handler = this.handlers.get(action.action_type);
    if (!handler) {
      throw new Error(`No handler registered for action type: ${action.action_type}`);
    }

    this.log.info({ actionId: action.id, actionType: action.action_type, targetId: action.target_id }, 'Executing action');
    updateActionStatus(action.id, 'executing');

    try {
      await handler(action);
      updateActionStatus(action.id, 'done');
      this.log.info({ actionId: action.id }, 'Action executed successfully');
    } catch (err) {
      const error = err as Error;
      this.log.error({ actionId: action.id, err: error.message }, 'Action execution failed');
      // Revert to approved so it can be retried
      updateActionStatus(action.id, 'approved');
      throw err;
    }
  }

  async executeMany(actions: AgentActionRow[]): Promise<{ succeeded: number; failed: number }> {
    let succeeded = 0;
    let failed = 0;

    for (const action of actions) {
      try {
        await this.execute(action);
        succeeded++;
      } catch {
        failed++;
      }
    }

    return { succeeded, failed };
  }
}

// Singleton executor with all Things handlers registered
export const thingsExecutor = new ActionExecutor();

thingsExecutor.register('things.update_notes', async (action) => {
  const payload = JSON.parse(action.payload) as { notes: string };
  const success = updateTaskNotes(action.target_id, payload.notes);
  if (!success) throw new Error(`Failed to update notes for task ${action.target_id}`);
});

thingsExecutor.register('things.add_tag', async (action) => {
  const payload = JSON.parse(action.payload) as { tag: string };
  const success = addTagToTask(action.target_id, payload.tag);
  if (!success) throw new Error(`Failed to add tag to task ${action.target_id}`);
});
