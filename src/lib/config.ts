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

// Path resolution based on environment
function getDbPath(): string {
  // Explicit env var always wins
  if (process.env.SELENE_DB_PATH) {
    return process.env.SELENE_DB_PATH;
  }
  // Test environment uses project-local test database
  if (isTestEnv) {
    return join(projectRoot, 'data-test/selene.db');
  }
  // Development environment uses dedicated dev data directory
  if (isDevEnv) {
    return join(devDataRoot, 'selene.db');
  }
  // Production default
  return join(homedir(), 'selene-data/selene.db');
}

function getVectorsPath(): string {
  if (process.env.SELENE_VECTORS_PATH) {
    return process.env.SELENE_VECTORS_PATH;
  }
  if (isTestEnv) {
    return join(projectRoot, 'data-test/vectors.lance');
  }
  if (isDevEnv) {
    return join(devDataRoot, 'vectors.lance');
  }
  return join(homedir(), 'selene-data/vectors.lance');
}

function getVaultPath(): string {
  if (process.env.SELENE_VAULT_PATH) {
    return process.env.SELENE_VAULT_PATH;
  }
  if (isTestEnv) {
    return join(projectRoot, 'data-test/vault');
  }
  if (isDevEnv) {
    return join(devDataRoot, 'vault');
  }
  return join(projectRoot, 'vault');
}

function getDigestsPath(): string {
  if (process.env.SELENE_DIGESTS_PATH) {
    return process.env.SELENE_DIGESTS_PATH;
  }
  if (isTestEnv) {
    return join(projectRoot, 'data-test/digests');
  }
  if (isDevEnv) {
    return join(devDataRoot, 'digests');
  }
  return join(projectRoot, 'data', 'digests');
}

function getLogsPath(): string {
  if (process.env.SELENE_LOGS_PATH) {
    return process.env.SELENE_LOGS_PATH;
  }
  if (isTestEnv) {
    return join(projectRoot, 'logs');
  }
  if (isDevEnv) {
    return join(devDataRoot, 'logs');
  }
  return join(projectRoot, 'logs');
}

export const config = {
  // Environment
  env: seleneEnv as 'production' | 'development' | 'test',
  isTestEnv,
  isDevEnv,

  // Paths - environment-aware
  dbPath: getDbPath(),
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

  // iMessage digest delivery
  imessageDigestEnabled: !isTestEnv && !isDevEnv && !!process.env.IMESSAGE_DIGEST_RECIPIENT && process.env.IMESSAGE_DIGEST_ENABLED !== 'false',
  imessageDigestRecipient: process.env.IMESSAGE_DIGEST_RECIPIENT || '',

  // API authentication
  apiToken: process.env.SELENE_API_TOKEN || '',

  // APNs push notifications
  apnsKeyPath: process.env.APNS_KEY_PATH || '',
  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsTeamId: process.env.APNS_TEAM_ID || '',
  apnsBundleId: process.env.APNS_BUNDLE_ID || 'com.selene.mobile',
  apnsProduction: process.env.APNS_PRODUCTION === 'true',

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
};
