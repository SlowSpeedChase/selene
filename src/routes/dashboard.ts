import type { FastifyInstance } from 'fastify';
import {
  getAgentRegistry,
  getPausedJobs,
  getPendingActions,
  getAllReports,
  AgentActionRow,
  AgentRegistryRow,
  AgentReportRow,
} from '../lib/agent-db';

function html(content: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Selene</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; color: #1a1a1a; }
    nav { background: #fff; border-bottom: 1px solid #e0e0e0; padding: 12px 24px; display: flex; gap: 24px; align-items: center; }
    nav a { text-decoration: none; color: #666; font-size: 14px; }
    nav a:hover { color: #000; }
    nav .brand { font-weight: 600; color: #000; margin-right: 8px; }
    main { max-width: 900px; margin: 32px auto; padding: 0 24px; }
    h1 { font-size: 22px; font-weight: 600; margin-bottom: 24px; }
    h2 { font-size: 16px; font-weight: 600; margin-bottom: 12px; color: #333; }
    .card { background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 100px; font-size: 12px; font-weight: 500; }
    .badge-pending  { background: #fff3cd; color: #856404; }
    .badge-running  { background: #d1ecf1; color: #0c5460; }
    .badge-paused   { background: #f8d7da; color: #721c24; }
    .badge-done     { background: #d4edda; color: #155724; }
    .badge-enabled  { background: #d4edda; color: #155724; }
    .badge-disabled { background: #f5f5f5; color: #666; }
    .action-card { border: 1px solid #e0e0e0; border-radius: 6px; padding: 14px 16px; margin-bottom: 10px; }
    .action-meta { font-size: 12px; color: #666; margin-bottom: 6px; }
    .action-rationale { font-size: 13px; color: #444; margin: 6px 0; }
    .confidence { font-size: 12px; color: #888; }
    .btn { display: inline-block; padding: 6px 14px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer; border: none; text-decoration: none; }
    .btn-approve { background: #198754; color: #fff; }
    .btn-reject  { background: #fff; color: #dc3545; border: 1px solid #dc3545; }
    .btn-approve:hover { background: #157347; }
    .btn-reject:hover  { background: #dc3545; color: #fff; }
    .btn-group { display: flex; gap: 8px; margin-top: 10px; }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    .stat { font-size: 28px; font-weight: 700; }
    .stat-label { font-size: 13px; color: #666; margin-top: 2px; }
    pre { background: #f8f8f8; border: 1px solid #e0e0e0; border-radius: 4px; padding: 10px; font-size: 12px; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { text-align: left; padding: 8px 10px; border-bottom: 2px solid #e0e0e0; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.05em; }
    td { padding: 8px 10px; border-bottom: 1px solid #f0f0f0; }
    .report-body { white-space: pre-wrap; font-size: 13px; line-height: 1.6; }
    .empty { color: #999; font-size: 14px; padding: 20px 0; }
  </style>
</head>
<body>
  <nav>
    <span class="brand">Selene</span>
    <a href="/dashboard">Home</a>
    <a href="/dashboard/queue">Approval Queue</a>
    <a href="/dashboard/reports">Reports</a>
    <a href="/dashboard/agents">Agents</a>
  </nav>
  <main>${content}</main>
</body>
</html>`;
}

function badgeStatus(status: string): string {
  const classes: Record<string, string> = {
    pending: 'badge-pending', running: 'badge-running', paused: 'badge-paused',
    complete: 'badge-done', done: 'badge-done', approved: 'badge-done',
    rejected: 'badge-disabled', error: 'badge-paused',
  };
  return `<span class="badge ${classes[status] ?? 'badge-pending'}">${status}</span>`;
}

export async function dashboardRoutes(fastify: FastifyInstance): Promise<void> {

  fastify.get('/dashboard', async (_req, reply) => {
    const agents = getAgentRegistry();
    const pausedJobs = getPausedJobs();
    const pendingActions = getPendingActions();

    const agentCards = agents.map((a: AgentRegistryRow) => `
      <div class="card">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div>
            <strong>${a.agent_name}</strong>
            <span class="badge ${a.enabled ? 'badge-enabled' : 'badge-disabled'}" style="margin-left:8px">${a.enabled ? 'enabled' : 'disabled'}</span>
          </div>
          <div style="font-size:12px;color:#888">Last run: ${a.last_run_at ? new Date(a.last_run_at).toLocaleString() : 'never'}</div>
        </div>
        <div style="font-size:13px;color:#555;margin-top:6px">${a.description}</div>
      </div>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Selene Dashboard</h1>
      <div class="grid-2" style="margin-bottom:24px">
        <div class="card">
          <div class="stat">${pendingActions.length}</div>
          <div class="stat-label">Actions awaiting approval</div>
          ${pendingActions.length > 0 ? '<a href="/dashboard/queue" class="btn btn-approve" style="margin-top:12px;display:inline-block">Review Queue</a>' : ''}
        </div>
        <div class="card">
          <div class="stat">${pausedJobs.length}</div>
          <div class="stat-label">Jobs paused (awaiting input)</div>
        </div>
      </div>
      <h2>Agents</h2>
      ${agentCards || '<p class="empty">No agents registered yet.</p>'}
    `);
  });

  fastify.get('/dashboard/queue', async (_req, reply) => {
    const actions = getPendingActions();

    const actionCards = actions.map((a: AgentActionRow) => {
      const payload = JSON.parse(a.payload) as Record<string, unknown>;
      return `
        <div class="action-card">
          <div class="action-meta">${badgeStatus(a.status)} &nbsp; <strong>${a.action_type}</strong> on <code>${a.target_id}</code></div>
          <div class="action-rationale">${a.rationale}</div>
          <div class="confidence">Confidence: ${(a.confidence * 100).toFixed(0)}%</div>
          <pre>${JSON.stringify(payload, null, 2)}</pre>
          <div class="btn-group">
            <button class="btn btn-approve" onclick="approveAction('${a.id}')">Approve</button>
            <button class="btn btn-reject"  onclick="rejectAction('${a.id}')">Reject</button>
          </div>
        </div>
      `;
    }).join('');

    reply.type('text/html');
    return html(`
      <h1>Approval Queue <span style="font-size:16px;font-weight:400;color:#666">${actions.length} pending</span></h1>
      ${actionCards || '<p class="empty">No pending actions. Agents are up to date.</p>'}
      <script>
        async function approveAction(id) {
          await fetch('/agents/actions/' + id + '/approve', { method: 'POST' });
          location.reload();
        }
        async function rejectAction(id) {
          await fetch('/agents/actions/' + id + '/reject', { method: 'POST' });
          location.reload();
        }
      </script>
    `);
  });

  fastify.get('/dashboard/reports', async (_req, reply) => {
    const reports = getAllReports(50);

    const reportCards = reports.map((r: AgentReportRow) => `
      <div class="card">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
          <strong>${r.title}</strong>
          <span style="font-size:12px;color:#888">${new Date(r.created_at).toLocaleString()}</span>
        </div>
        <div class="report-body">${r.body}</div>
      </div>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Agent Reports</h1>
      ${reportCards || '<p class="empty">No reports yet. Agents haven\'t run.</p>'}
    `);
  });

  fastify.get('/dashboard/agents', async (_req, reply) => {
    const agents = getAgentRegistry();

    const rows = agents.map((a: AgentRegistryRow) => `
      <tr>
        <td><strong>${a.agent_name}</strong></td>
        <td>${a.description}</td>
        <td>${badgeStatus(a.enabled ? 'enabled' : 'disabled')}</td>
        <td>${a.last_run_at ? new Date(a.last_run_at).toLocaleString() : '—'}</td>
        <td>
          ${a.enabled
            ? `<button class="btn btn-reject" onclick="setEnabled('${a.agent_name}', false)">Disable</button>`
            : `<button class="btn btn-approve" onclick="setEnabled('${a.agent_name}', true)">Enable</button>`
          }
        </td>
      </tr>
    `).join('');

    reply.type('text/html');
    return html(`
      <h1>Agent Manager</h1>
      <div class="card">
        <table>
          <thead><tr><th>Agent</th><th>Description</th><th>Status</th><th>Last Run</th><th>Actions</th></tr></thead>
          <tbody>${rows || '<tr><td colspan="5" class="empty">No agents registered</td></tr>'}</tbody>
        </table>
      </div>
      <script>
        async function setEnabled(name, enabled) {
          await fetch('/agents/' + name + '/' + (enabled ? 'enable' : 'disable'), { method: 'POST' });
          location.reload();
        }
      </script>
    `);
  });
}
