import { execFileSync } from 'node:child_process';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadServiceConfig } from './service-config.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const target = process.argv[3] || 'curator';
if (!['curator', 'dashboard'].includes(target)) throw new Error('Serviço desconhecido.');
const label = target === 'dashboard' ? 'com.edromeroc.shadowing-curator-dashboard' : 'com.edromeroc.shadowing-curator';
const agentPath = path.join(os.homedir(), 'Library', 'LaunchAgents', `${label}.plist`);
const logs = path.join(os.homedir(), 'Library', 'Logs');
const service = `gui/${process.getuid()}/${label}`;
const domain = `gui/${process.getuid()}`;
const action = process.argv[2];
const logName = target === 'dashboard' ? 'ShadowingCuratorDashboard' : 'ShadowingCurator';

function escapeXML(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function launchctl(...arguments_) {
  return execFileSync('/bin/launchctl', arguments_, { stdio: 'pipe', encoding: 'utf8' });
}

if (action === 'install') {
  if (target === 'curator') {
    try {
      await loadServiceConfig(undefined, path.resolve(root, '../..'));
    } catch (error) {
      console.error(error.message);
      process.exit(1);
    }
  }
  await mkdir(path.dirname(agentPath), { recursive: true });
  await mkdir(logs, { recursive: true });
  const arguments_ = target === 'dashboard' ? [process.execPath, path.join(root, 'dashboard.mjs')] :
    ['/usr/bin/caffeinate', '-s', process.execPath, path.join(root, 'run-service.mjs')];
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array>${arguments_.map((item) => `<string>${escapeXML(item)}</string>`).join('')}</array>
<key>WorkingDirectory</key><string>${escapeXML(root)}</string>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>60</integer>
<key>StandardOutPath</key><string>${escapeXML(path.join(logs, `${logName}.log`))}</string>
<key>StandardErrorPath</key><string>${escapeXML(path.join(logs, `${logName}.error.log`))}</string>
</dict></plist>
`;
  try { launchctl('bootout', domain, agentPath); } catch {}
  await writeFile(agentPath, plist, { mode: 0o644 });
  launchctl('bootstrap', domain, agentPath);
  console.log(`Serviço instalado e iniciado: ${agentPath}`);
} else if (action === 'status') {
  try { console.log(launchctl('print', service)); } catch { console.log('Serviço não está ativo.'); }
} else if (action === 'uninstall') {
  try { launchctl('bootout', domain, agentPath); } catch {}
  await rm(agentPath, { force: true });
  console.log('Serviço removido; candidatos e catálogo mantidos.');
} else {
  throw new Error('Use: npm run service:install, service:status ou service:uninstall.');
}
