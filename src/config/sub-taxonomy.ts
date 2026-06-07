import type { Category } from '../lib/prompts';

/**
 * Seed sub-taxonomy: each of the 8 fixed categories → its closed-set sub-categories.
 *
 * THIS FILE IS THE PRECIOUS LAYER. Git tracks it, so a fact-store `rebuild` of
 * selene.db cannot wipe it. To curate the taxonomy, edit this file (and re-run the
 * backfill). All names here are `firm` by declaration (Phase 2 firmness gradient).
 *
 * Keep lists SHORT and content-free-ish — these are facets, not source buckets.
 */
export const SUB_TAXONOMY: Record<Category, string[]> = {
  'Personal Growth':        ['Habits', 'Reflection', 'Learning', 'Identity'],
  'Relationships & Social': ['Family', 'Friends', 'Partner', 'Community'],
  'Health & Body':          ['Running', 'Sleep', 'Diet', 'Strength', 'Mental Health'],
  'Projects & Tech':        ['Selene', 'Side Projects', 'Tooling', 'Infrastructure'],
  'Career & Work':          ['Job', 'Skills', 'Networking', 'Finances'],
  'Creativity & Expression':['Writing', 'Music', 'Art', 'Ideas'],
  'Politics & Society':     ['Policy', 'Economics', 'Culture', 'Environment'],
  'Daily Systems':          ['Planning', 'Errands', 'Routines', 'Tools'],
};

export function subCategoriesFor(category: string): string[] {
  return (SUB_TAXONOMY as Record<string, string[]>)[category] ?? [];
}
