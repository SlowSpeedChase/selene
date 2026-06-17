import { join } from 'path';
import { homedir } from 'os';
import { config as loadEnv } from 'dotenv';

// Load environment variables from .env file
loadEnv();

// Load .env.development only when not explicitly set to production
// (SeleneChat sets SELENE_ENV=production when launching workflows)
if (process.env.SELENE_ENV !== 'production') {
  loadEnv({ path: join(__dirname, '../..', '.env.development'), override: true });
}

const projectRoot = join(__dirname, '../..');

// Environment: 'test', 'development', or 'production' (default)
const seleneEnv = process.env.SELENE_ENV || 'production';
const isTestEnv = seleneEnv === 'test';
const isDevEnv = seleneEnv === 'development';
const devDataRoot = join(homedir(), 'selene-data-dev');

// Path resolution based on environment.
//
// The four-branch ladder (explicit env var → test → dev → prod default) is identical
// across five getters; only the concrete paths differ. `resolvePath` captures the ladder
// once. The test/dev/prod paths are passed in pre-resolved (not derived from a relative
// segment) so each getter reproduces its EXACT current values with no uniform-scheme
// assumption — e.g. getLogsPath's test path is `projectRoot/logs` (same as prod), NOT
// `projectRoot/data-test/logs`.
function resolvePath(
  envVarValue: string | undefined,
  testAbs: string,
  devAbs: string,
  prodAbs: string,
): string {
  // Explicit env var always wins
  if (envVarValue) {
    return envVarValue;
  }
  // Test environment
  if (isTestEnv) {
    return testAbs;
  }
  // Development environment uses dedicated dev data directory
  if (isDevEnv) {
    return devAbs;
  }
  // Production default
  return prodAbs;
}

function getDbPath(): string {
  return resolvePath(
    process.env.SELENE_DB_PATH,
    join(projectRoot, 'data-test/selene.db'),
    join(devDataRoot, 'selene.db'),
    join(homedir(), 'selene-data/selene.db'),
  );
}

function getFactsDbPath(): string {
  return resolvePath(
    process.env.SELENE_FACTS_DB_PATH,
    join(projectRoot, 'data-test/facts.db'),
    join(devDataRoot, 'facts.db'),
    join(homedir(), 'selene-data/facts.db'),
  );
}

function getVectorsPath(): string {
  return resolvePath(
    process.env.SELENE_VECTORS_PATH,
    join(projectRoot, 'data-test/vectors.lance'),
    join(devDataRoot, 'vectors.lance'),
    join(homedir(), 'selene-data/vectors.lance'),
  );
}

/**
 * Resolve the Obsidian vault path per environment. Pure (all inputs explicit) so it's unit-testable.
 *
 * THE dev→prod leak guard: in development the vault is ALWAYS the dev sandbox — never an externally
 * configured path — EXCEPT an explicit `/tmp` scratch (how the test/cutover harnesses redirect it).
 * This stops the prod `.env`'s `SELENE_VAULT_PATH` (the real iCloud vault) from leaking into a dev run
 * and polluting production from dev. Production honors the operator-configured `SELENE_VAULT_PATH`
 * (set via the prod launchd plist); test honors an explicit override, else the test sandbox.
 */
export function resolveVaultPath(opts: {
  env: string;
  envVaultPath?: string;
  devDataRoot: string;
  projectRoot: string;
}): string {
  const { env, envVaultPath, devDataRoot: devRoot, projectRoot: proj } = opts;
  if (env === 'test') {
    return envVaultPath || join(proj, 'data-test/vault');
  }
  if (env === 'development') {
    if (envVaultPath && envVaultPath.startsWith('/tmp/')) return envVaultPath; // test/cutover scratch
    return join(devRoot, 'vault');
  }
  if (envVaultPath) return envVaultPath;
  return join(proj, 'vault');
}

function getVaultPath(): string {
  return resolveVaultPath({
    env: seleneEnv,
    envVaultPath: process.env.SELENE_VAULT_PATH,
    devDataRoot,
    projectRoot,
  });
}

function getDigestsPath(): string {
  return resolvePath(
    process.env.SELENE_DIGESTS_PATH,
    join(projectRoot, 'data-test/digests'),
    join(devDataRoot, 'digests'),
    join(projectRoot, 'data', 'digests'),
  );
}

function getLogsPath(): string {
  // NOTE: the test path is `projectRoot/logs` (identical to prod) — NOT `data-test/logs`.
  return resolvePath(
    process.env.SELENE_LOGS_PATH,
    join(projectRoot, 'logs'),
    join(devDataRoot, 'logs'),
    join(projectRoot, 'logs'),
  );
}

export const config = {
  // Environment
  env: seleneEnv as 'production' | 'development' | 'test',
  isTestEnv,
  isDevEnv,

  // Paths - environment-aware
  dbPath: getDbPath(),
  factsDbPath: getFactsDbPath(),
  vectorsPath: getVectorsPath(),
  vaultPath: getVaultPath(),
  digestsPath: getDigestsPath(),
  logsPath: getLogsPath(),
  projectRoot,

  // Ollama - same config as before
  ollamaUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  ollamaModel: process.env.OLLAMA_MODEL || 'mistral:7b',
  embeddingModel: process.env.OLLAMA_EMBED_MODEL || 'nomic-embed-text',

  // Server
  port: parseInt(process.env.PORT || (isDevEnv ? '5679' : '5678'), 10),
  host: process.env.HOST || '0.0.0.0',

  // Things bridge - unchanged
  thingsPendingDir: join(projectRoot, 'scripts/things-bridge/pending'),

  // Apple Notes digest - disabled in test and dev mode
  appleNotesDigestEnabled: !isTestEnv && !isDevEnv && process.env.APPLE_NOTES_DIGEST_ENABLED !== 'false',

  // TRMNL e-ink display digest
  trmnlWebhookUrl: process.env.TRMNL_WEBHOOK_URL || '',
  trmnlDigestEnabled: !isTestEnv && !isDevEnv && !!process.env.TRMNL_WEBHOOK_URL && process.env.TRMNL_DIGEST_ENABLED !== 'false',

  // API authentication
  apiToken: process.env.SELENE_API_TOKEN || '',

  // APNs push notifications
  apnsKeyPath: process.env.APNS_KEY_PATH || '',
  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsTeamId: process.env.APNS_TEAM_ID || '',
  apnsBundleId: process.env.APNS_BUNDLE_ID || 'com.selene.mobile',
  apnsProduction: process.env.APNS_PRODUCTION === 'true',

  // E-ink notebook ingestion
  einkWatchDir:
    process.env.EINK_WATCH_DIR ||
    join(homedir(), 'Library/Mobile Documents/com~apple~CloudDocs/Documents/iCloud Kindle Notebooks'),
  einkArchiveDir: process.env.EINK_ARCHIVE_DIR || join(homedir(), 'selene-data/eink/archive'),
  einkTempDir: process.env.EINK_TEMP_DIR || join(homedir(), 'selene-data/eink/pages'),
  einkManifestPath: process.env.EINK_MANIFEST_PATH || join(homedir(), 'selene-data/eink/.processed.json'),
  einkVisionModel: process.env.EINK_VISION_MODEL || 'qwen2.5vl:7b',

  // Voice Memos transcription
  voiceMemosRecordingsDir:
    process.env.VOICE_MEMOS_RECORDINGS_DIR ||
    join(homedir(), 'Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings'),
  voiceMemosOutputDir: process.env.VOICE_MEMOS_OUTPUT_DIR || join(homedir(), 'VoiceMemos'),
  whisperBinary:
    process.env.WHISPER_BINARY || join(homedir(), '.local/whisper.cpp/build/bin/whisper-cli'),
  whisperModel:
    process.env.WHISPER_MODEL || join(homedir(), '.local/whisper.cpp/models/ggml-medium.bin'),
  whisperThreads: parseInt(process.env.WHISPER_THREADS || '6', 10),
  seleneWebhookUrl:
    process.env.SELENE_WEBHOOK_URL || 'http://localhost:5678/webhook/api/drafts',
  kitchenosApiUrl: process.env.KITCHENOS_API_URL || 'http://localhost:5001',
};
