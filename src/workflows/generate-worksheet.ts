import type { Worksheet } from '../types/worksheets';

export function buildTodayWorksheet(now: Date = new Date()): Worksheet {
  const date = now.toISOString().slice(0, 10);
  return {
    id: `ws_${date}`,
    title: `Daily Review — ${date}`,
    fields: [
      {
        id: 'f1',
        kind: 'free_capture',
        prompt: "Anything on your mind? Write it and it'll become a note.",
        binding: { action: 'new_note' },
      },
    ],
  };
}
