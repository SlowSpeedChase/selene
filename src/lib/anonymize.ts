export interface AnonymizeResult {
  text: string;
  tokenMap: Record<string, string>; // token → original value (store locally, never share)
}

// Regex patterns for structured PII
const PII_PATTERNS: Array<{ label: string; pattern: RegExp }> = [
  { label: 'EMAIL',   pattern: /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g },
  { label: 'PHONE',   pattern: /(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}/g },
  { label: 'URL',     pattern: /https?:\/\/[^\s"'<>]+/g },
  { label: 'UUID',    pattern: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi },
];

export function anonymize(text: string): AnonymizeResult {
  const tokenMap: Record<string, string> = {};
  const counters: Record<string, number> = {};
  let result = text;

  for (const { label, pattern } of PII_PATTERNS) {
    pattern.lastIndex = 0;
    result = result.replace(pattern, (match) => {
      const existingToken = Object.keys(tokenMap).find((k) => tokenMap[k] === match);
      if (existingToken) return existingToken;

      counters[label] = (counters[label] ?? 0) + 1;
      const token = `[${label}_${counters[label]}]`;
      tokenMap[token] = match;
      return token;
    });
  }

  return { text: result, tokenMap };
}

export function deanonymize(text: string, tokenMap: Record<string, string>): string {
  let result = text;
  for (const [token, original] of Object.entries(tokenMap)) {
    result = result.split(token).join(original);
  }
  return result;
}

export function anonymizeForDebug(text: string): string {
  return anonymize(text).text;
}

/**
 * Two-pass anonymization: regex (structured PII) + Ollama NER (contextual PII).
 * The NER pass is gracefully skipped if Ollama is unavailable.
 * Store the returned tokenMap locally — never share it alongside the anonymized text.
 */
export async function anonymizeWithNER(text: string): Promise<AnonymizeResult> {
  // Pass 1: regex
  const { text: afterRegex, tokenMap } = anonymize(text);

  // Pass 2: Ollama NER for names, orgs, account refs
  try {
    const { generate } = await import('./ollama');
    const prompt = `You are a privacy filter. Identify all names of people, places, organizations, and account references in this text. Return ONLY a JSON array of objects: [{"original":"John Smith","label":"PERSON"},{"original":"Acme Corp","label":"ORG"},...]. If none found, return [].

Text:
${afterRegex}`;

    const response = await generate(prompt, { timeoutMs: 30000, temperature: 0 });
    const jsonMatch = response.match(/\[[\s\S]*\]/);
    if (!jsonMatch) return { text: afterRegex, tokenMap };

    const entities = JSON.parse(jsonMatch[0]) as Array<{ original: string; label: string }>;
    const labelCounts: Record<string, number> = {};
    let result = afterRegex;

    for (const entity of entities) {
      if (!entity.original || entity.original.length < 2) continue;
      const label = entity.label ?? 'ENTITY';
      // Skip if already replaced by regex pass
      if (Object.values(tokenMap).includes(entity.original)) continue;
      labelCounts[label] = (labelCounts[label] ?? 0) + 1;
      const token = `[${label}_${labelCounts[label]}]`;
      tokenMap[token] = entity.original;
      result = result.split(entity.original).join(token);
    }

    return { text: result, tokenMap };
  } catch {
    // Ollama unavailable — return regex-only result
    return { text: afterRegex, tokenMap };
  }
}
