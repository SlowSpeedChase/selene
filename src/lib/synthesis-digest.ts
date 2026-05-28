import type { Database } from 'better-sqlite3';

export function buildSynthesisSections(db: Database): string {
  const sections: string[] = [];

  // Section 1: Topics circling
  const clusters = db.prepare(`
    SELECT name, note_count, synthesis_text
    FROM topic_clusters
    WHERE is_proto = 0
      AND synthesis_updated_at > datetime('now', '-7 days')
    ORDER BY note_count DESC
    LIMIT 3
  `).all() as Array<{ name: string; note_count: number; synthesis_text: string | null }>;

  const topClusters = clusters.length > 0
    ? clusters
    : db.prepare(`
        SELECT name, note_count, synthesis_text
        FROM topic_clusters
        WHERE is_proto = 0 AND synthesis_text IS NOT NULL
        ORDER BY note_count DESC
        LIMIT 3
      `).all() as Array<{ name: string; note_count: number; synthesis_text: string | null }>;

  if (topClusters.length > 0) {
    const lines = topClusters.map(c => {
      const clean = c.synthesis_text?.replace(/^\s*\d+\.\s*/, '') ?? '';
      const first = clean.split('.')[0]?.trim() ?? '';
      const preview = first ? first + '.' : '';
      return preview
        ? `${c.name} (${c.note_count} notes) — ${preview}`
        : `${c.name} (${c.note_count} notes)`;
    });
    sections.push(`Topics circling\n\n${lines.join('\n\n')}`);
  }

  // Section 2: Understanding shifted (evolution detection — Signal A)
  const evolutions = db.prepare(`
    SELECT name, evolution_summary
    FROM topic_clusters
    WHERE evolution_detected_at > datetime('now', '-1 day')
      AND is_proto = 0
      AND evolution_summary IS NOT NULL
    ORDER BY evolution_detected_at DESC
    LIMIT 2
  `).all() as Array<{ name: string; evolution_summary: string }>;

  if (evolutions.length > 0) {
    const lines = evolutions.map(e => `${e.name}: ${e.evolution_summary}`);
    sections.push(`Understanding shifted\n\n${lines.join('\n')}`);
  }

  // Section 3: Unexpected connections (Signal C)
  const connections = db.prepare(`
    SELECT
      src.title AS source_title,
      tgt.title AS target_title,
      nc.similarity_score,
      tgt.created_at AS target_created_at
    FROM note_connections nc
    JOIN raw_notes src ON nc.source_note_id = src.id
    JOIN raw_notes tgt ON nc.target_note_id = tgt.id
    WHERE nc.found_at > datetime('now', '-1 day')
      AND src.test_run IS NULL
    ORDER BY nc.similarity_score DESC
    LIMIT 3
  `).all() as Array<{
    source_title: string;
    target_title: string;
    similarity_score: number;
    target_created_at: string;
  }>;

  if (connections.length > 0) {
    const lines = connections.map(c => {
      const pct = Math.round(c.similarity_score * 100);
      const targetDate = new Date(c.target_created_at).toLocaleDateString('en-US', {
        month: 'short',
        year: 'numeric',
      });
      return `"${c.source_title}" → "${c.target_title}" (${targetDate}, ${pct}% match)`;
    });
    sections.push(`Unexpected connections\n\n${lines.join('\n')}`);
  }

  // Section 4: Pattern forming (proto-clusters, Signal B) or Sunday weekly rollup
  const isSunday = new Date().getDay() === 0;

  if (isSunday) {
    const rollup = db.prepare(
      `SELECT value FROM synthesis_meta WHERE key = 'weekly_evolution'`
    ).get() as { value: string } | undefined;

    if (rollup) {
      sections.push(`This week in your thinking\n\n${rollup.value}`);
    }
  } else {
    const protoClusters = db.prepare(`
      SELECT name, note_count
      FROM topic_clusters
      WHERE is_proto = 1
        AND created_at > datetime('now', '-3 days')
      ORDER BY note_count DESC
      LIMIT 2
    `).all() as Array<{ name: string; note_count: number }>;

    if (protoClusters.length > 0) {
      const lines = protoClusters.map(
        p => `${p.note_count} recent notes circling "${p.name}" — not a full cluster yet.`
      );
      sections.push(`Pattern forming\n\n${lines.join('\n')}`);
    }
  }

  if (sections.length === 0) return '';
  return '\n\n' + sections.map(s => `## ${s}`).join('\n\n');
}
