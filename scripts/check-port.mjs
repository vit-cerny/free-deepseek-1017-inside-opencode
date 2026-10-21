// Verify the dsh-our-free-model local forward port that this repo wires up.
//
//   node scripts/check-port.mjs                  -> roster only
//   node scripts/check-port.mjs deepseek-v4.1-flash-free   -> roster + one real completion
//
// Key: DSH_OFM_API_KEY from the environment, else forwardKey from the plugin settings.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const dshHome = process.env.DSH_HOME || join(homedir(), '.dsh');
const settingsPath = join(dshHome, 'our-free-model', 'settings.json');

let settings = {};
try { settings = JSON.parse(readFileSync(settingsPath, 'utf8')); } catch { /* reported below */ }
const key = process.env.DSH_OFM_API_KEY || settings.forwardKey || '';
const port = settings.forward?.port ?? 18899;
const base = `http://127.0.0.1:${port}`;

if (!settings.forward) {
  console.error(`plugin settings not found at ${settingsPath}`);
  process.exit(1);
}
if (!settings.forward.enabled) {
  console.error('local forward is switched off - run install.ps1 or enable it in DSH > Settings > Our Free Model');
  process.exit(1);
}
if (!key) {
  console.error('no forward key: start DSH Desktop once so the plugin mints one, then re-run');
  process.exit(1);
}

const health = await fetch(`${base}/health`).then(r => r.json()).catch(() => null);
if (!health?.ok) {
  console.error(`nothing healthy on ${base} - is DSH Desktop running?`);
  process.exit(1);
}

const res = await fetch(`${base}/v1/models`, { headers: { authorization: `Bearer ${key}` } });
if (!res.ok) {
  console.error(`/v1/models -> HTTP ${res.status}`);
  process.exit(1);
}
const roster = await res.json();
console.log(`port:   ${base}`);
console.log(`roster: ${roster.data.length} model ids`);

const model = process.argv[2];
if (!model) process.exit(0);

const t0 = Date.now();
const completion = await fetch(`${base}/v1/chat/completions`, {
  method: 'POST',
  headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
  body: JSON.stringify({
    model,
    messages: [{ role: 'user', content: 'Reply with exactly: FREE_OK' }],
    max_tokens: 64,
  }),
});
const text = await completion.text();
console.log(`model:  ${model}`);
console.log(`status: HTTP ${completion.status} in ${Date.now() - t0} ms`);
console.log(text.slice(0, 600));
process.exit(completion.ok ? 0 : 1);
