'use strict';
// Uçtan uca duman testi: REST + WS terminal. Agent'ı kendisi başlatır ve kapatır.
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = 18787;
const HOST = '127.0.0.1';
let TOKEN = '';

function get(p) {
  return fetch(`http://${HOST}:${PORT}${p}`, { headers: { Authorization: `Bearer ${TOKEN}` } })
    .then(r => r.json());
}
function post(p, body) {
  return fetch(`http://${HOST}:${PORT}${p}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }).then(r => r.json());
}

async function main() {
  const agent = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'server.js')], {
    env: { ...process.env, CLAUDE_REMOTE_HOST: HOST, CLAUDE_REMOTE_PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  agent.stdout.on('data', d => {
    const m = d.toString().match(/token: (\w+)/);
    if (m) TOKEN = m[1];
  });
  agent.stderr.on('data', d => process.stderr.write('[agent] ' + d));

  // sunucu + token hazır olana kadar bekle
  for (let i = 0; i < 50 && !TOKEN; i++) await new Promise(r => setTimeout(r, 100));
  if (!TOKEN) throw new Error('agent başlamadı');

  const results = [];
  const check = (name, ok, extra) => { results.push([name, ok, extra]); console.log(`${ok ? 'OK ' : 'FAIL'} ${name}${extra ? ' — ' + extra : ''}`); };

  const health = await fetch(`http://${HOST}:${PORT}/api/health`).then(r => r.json());
  check('health', health.ok === true);

  const noAuth = await fetch(`http://${HOST}:${PORT}/api/projects`).then(r => r.status);
  check('auth reddi (401)', noAuth === 401);

  const projects = (await get('/api/projects')).projects;
  check('projects', Array.isArray(projects) && projects.length > 0, `${projects.length} proje, ilki: ${projects[0]?.name}`);

  const sess = (await get(`/api/sessions?project=${encodeURIComponent(projects[0].dir)}`)).sessions;
  check('sessions', Array.isArray(sess) && sess.length > 0, `${sess.length} oturum, özet: ${(sess[0]?.summary || '').slice(0, 60)}`);

  const chatRes = await get(`/api/chat?project=${encodeURIComponent(projects[0].dir)}&id=${sess[0].id}&limit=10`);
  check('chat', Array.isArray(chatRes.messages), `${chatRes.total} mesaj toplam, son ${chatRes.messages.length} geldi`);

  const files = await get('/api/files?path=' + encodeURIComponent('C:\\kumas_final'));
  check('files', files.entries && files.entries.length > 0, `${files.entries.length} girdi`);

  const st = await get('/api/stats');
  check('stats', typeof st.cpu === 'number' && st.memTotal > 0, `cpu=${st.cpu}% disks=${st.disks.length}`);

  // Terminal: PowerShell modu ile gerçek PTY testi
  const term = await post('/api/terminals', { cwd: 'C:\\kumas_final', mode: 'shell', cols: 100, rows: 30 });
  check('terminal oluşturma', !!term.id, term.title);

  const output = await new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://${HOST}:${PORT}/ws/terminal?id=${term.id}&token=${TOKEN}`);
    let buf = '';
    const timer = setTimeout(() => { ws.close(); resolve(buf); }, 12000);
    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'resize', cols: 100, rows: 30 }));
      setTimeout(() => ws.send(Buffer.from('echo MERHABA_$(1000+337)\r')), 2500);
    });
    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        buf += data.toString('utf8');
        if (buf.includes('MERHABA_1337')) { clearTimeout(timer); ws.close(); resolve(buf); }
      }
    });
    ws.on('error', reject);
  });
  check('terminal G/Ç (echo yanıtı)', output.includes('MERHABA_1337'));

  // Kaydet+durdur ve kayıtlı oturum listesi
  const saveRes = await post('/api/save-stop');
  check('save-stop', saveRes.saved === 1, `${saveRes.saved} oturum kaydedildi`);
  const list = await get('/api/terminals');
  check('kayıtlı oturum listede', list.saved.some(s => s.id === term.id));

  // Kayıtlı oturumdan devam (shell modu, scrollback preload)
  const resumed = await post('/api/terminals', { resumeSaved: term.id });
  check('resume', !!resumed.id && resumed.cwd.toLowerCase().includes('kumas_final'));
  const replay = await new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://${HOST}:${PORT}/ws/terminal?id=${resumed.id}&token=${TOKEN}`);
    let buf = '';
    const timer = setTimeout(() => { ws.close(); resolve(buf); }, 6000);
    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        buf += data.toString('utf8');
        if (buf.includes('önceki oturum kaydı') && buf.includes('MERHABA_1337')) {
          clearTimeout(timer); ws.close(); resolve(buf);
        }
      }
    });
    ws.on('error', reject);
  });
  check('resume scrollback replay', replay.includes('MERHABA_1337'));

  await post('/api/terminals/kill', { id: resumed.id });

  agent.kill();
  const fails = results.filter(r => !r[1]).length;
  console.log(`\n${results.length - fails}/${results.length} test geçti`);
  process.exit(fails ? 1 : 0);
}

main().catch(e => { console.error('HATA:', e); process.exit(1); });
