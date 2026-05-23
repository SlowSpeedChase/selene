export interface AnonymizeResult {
  text: string;
  tokenMap: Record<string, string>; // token → original value
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
