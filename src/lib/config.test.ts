import { join } from 'path';
import { config, resolveVaultPath } from './config';

describe('resolveVaultPath — dev must never inherit a leaked prod vault path', () => {
  const devRoot = '/Users/x/selene-data-dev';
  const proj = '/Users/x/selene';
  const prodVault = '/Users/x/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene';

  it('dev: REJECTS a leaked prod (iCloud) SELENE_VAULT_PATH and uses the dev sandbox', () => {
    expect(resolveVaultPath({ env: 'development', envVaultPath: prodVault, devDataRoot: devRoot, projectRoot: proj }))
      .toBe(join(devRoot, 'vault'));
  });
  it('dev: honors an explicit /tmp override (test/cutover harness redirect)', () => {
    expect(resolveVaultPath({ env: 'development', envVaultPath: '/tmp/t10-vault', devDataRoot: devRoot, projectRoot: proj }))
      .toBe('/tmp/t10-vault');
  });
  it('dev: no override → dev sandbox', () => {
    expect(resolveVaultPath({ env: 'development', devDataRoot: devRoot, projectRoot: proj }))
      .toBe(join(devRoot, 'vault'));
  });
  it('dev: a non-/tmp custom override is ignored in favor of the sandbox (isolation over convenience)', () => {
    expect(resolveVaultPath({ env: 'development', envVaultPath: '/Users/x/SomeOtherVault', devDataRoot: devRoot, projectRoot: proj }))
      .toBe(join(devRoot, 'vault'));
  });
  it('production: honors SELENE_VAULT_PATH (the operator-configured iCloud vault)', () => {
    expect(resolveVaultPath({ env: 'production', envVaultPath: prodVault, devDataRoot: devRoot, projectRoot: proj }))
      .toBe(prodVault);
  });
  it('production: no override → project-root vault', () => {
    expect(resolveVaultPath({ env: 'production', devDataRoot: devRoot, projectRoot: proj }))
      .toBe(join(proj, 'vault'));
  });
  it('test: honors an explicit override, else the test sandbox', () => {
    expect(resolveVaultPath({ env: 'test', envVaultPath: '/tmp/x', devDataRoot: devRoot, projectRoot: proj })).toBe('/tmp/x');
    expect(resolveVaultPath({ env: 'test', devDataRoot: devRoot, projectRoot: proj })).toBe(join(proj, 'data-test/vault'));
  });
});

describe('factsDbPath', () => {
  it('ends in facts.db', () => {
    expect(config.factsDbPath).toMatch(/facts\.db$/);
  });
  it('lives in the same directory as dbPath', () => {
    const dir = (p: string) => p.replace(/\/[^/]+$/, '');
    expect(dir(config.factsDbPath)).toBe(dir(config.dbPath));
  });
});
