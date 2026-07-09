'use strict';
// 'claude' modunun ConPTY üzerinde gerçekten açıldığını doğrular (TUI çıktısı bekler).
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = 18788;
const HOST = '127.0.0.1';
let TOKEN = '';

async function main() {
  const agent = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'server.js')], {
    env: { ...process.env, CLAUDE_REMOTE_HOST: HOST, CLAUDE_REMOTE_PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  agent.stdout.on('data', d => { const m = d.toString().match(/token: (\w+)/); if (m) TOKEN = m[1]; });
  for (let i = 0; i < 50 && !TOKEN; i++) await new Promise(r => setTimeout(r, 100));

  const term = await fetch(`http://${HOST}:${PORT}/api/terminals`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ cwd: 'C:\\kumas_final', mode: 'claude', cols: 120, rows: 35 }),
  }).then(r => r.json());
  console.log('terminal:', term);

  const out = await new Promise(resolve => {
    const ws = new WebSocket(`ws://${HOST}:${PORT}/ws/terminal?id=${term.id}&token=${TOKEN}`);
    let buf = '';
    const timer = setTimeout(() => { ws.close(); resolve(buf); }, 25000);
    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        buf += data.toString('utf8');
        if (buf.length > 2000) { clearTimeout(timer); ws.close(); resolve(buf); }
      }
    });
    ws.on('error', () => resolve(buf));
  });

  // ANSI temizle, ilk anlamlı içeriği göster
  const clean = out.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '').replace(/\x1b\][^\x07]*\x07/g, '');
  console.log('--- claude çıktısı (ilk 600 karakter) ---');
  console.log(clean.slice(0, 600));
  console.log('--- toplam', out.length, 'bayt geldi ---');

  await fetch(`http://${HOST}:${PORT}/api/terminals/kill`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: term.id }),
  });
  agent.kill();
  process.exit(out.length > 100 ? 0 : 1);
}
main().catch(e => { console.error(e); process.exit(1); });
