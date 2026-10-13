import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { loadServiceConfig } from './service-config.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
try {
  const requestedLimit = process.env.CURATOR_LIMIT;
  Object.assign(process.env, await loadServiceConfig(undefined, path.resolve(root, '../..')));
  if (requestedLimit !== undefined) process.env.CURATOR_LIMIT = requestedLimit;
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
delete process.env.CURATOR_OFFLINE;
if (!process.argv[2]) process.env.CURATOR_CONTINUOUS = '1';
process.argv[2] ||= 'scan';
await import('./curator.mjs');
