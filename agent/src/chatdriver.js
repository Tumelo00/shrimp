'use strict';
// Native sohbet sürücüsü: claude'u stream-json modunda çalıştırır, WS üzerinden
// çift yönlü köprüler. Mac prompt gönderir → claude stdin; claude stdout (JSON
// event'leri) → Mac. Böylece UI native chat render eder (terminal ham metni değil).
const { spawn } = require('child_process');
const { StringDecoder } = require('string_decoder');
const fs = require('fs');
const os = require('os');
const path = require('path');
const config = require('./config');

// Native chat oturumlarını "Sohbetler" listesinde göstermek için kaydet.
const NATIVE_JSON = path.join(os.homedir(), '.claude-remote', 'native-sessions.json');
function writeAtomic(file, data) {
  const tmp = `${file}.${process.pid}.tmp`;
  try { fs.writeFileSync(tmp, data); fs.renameSync(tmp, file); }
  catch { try { fs.writeFileSync(file, data); } catch { /* geç */ } }
}
function recordNative(id, cwd, title) {
  if (!id) return;
  let map = {};
  try { map = JSON.parse(fs.readFileSync(NATIVE_JSON, 'utf8')) || {}; } catch { /* yok */ }
  const prev = map[id] || {};
  map[id] = { id, cwd, title: title || prev.title || '', ts: Date.now() };
  // en yeni 60 oturumu tut
  const kept = Object.values(map).sort((a, b) => (b.ts || 0) - (a.ts || 0)).slice(0, 60);
  const out = {}; for (const e of kept) out[e.id] = e;
  try { fs.mkdirSync(path.dirname(NATIVE_JSON), { recursive: true }); writeAtomic(NATIVE_JSON, JSON.stringify(out)); } catch { /* geç */ }
}

const MODES = ['acceptEdits', 'auto', 'bypassPermissions', 'default', 'dontAsk', 'plan'];
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

function attach(ws, q) {
  const cwd = (q.cwd && fs.existsSync(q.cwd)) ? q.cwd : os.homedir();
  const args = ['/c', 'claude', '-p',
    '--input-format', 'stream-json',
    '--output-format', 'stream-json',
    '--include-partial-messages', '--verbose'];
  if (q.resume && /^[\w-]+$/.test(String(q.resume))) args.push('--resume', String(q.resume));
  if (q.model && /^[\w.\-]{1,60}$/.test(String(q.model))) args.push('--model', String(q.model));
  args.push('--permission-mode', MODES.includes(String(q.permissionMode)) ? String(q.permissionMode) : 'bypassPermissions');
  if (q.effort && EFFORTS.includes(String(q.effort))) args.push('--effort', String(q.effort));

  // Headless -p abonelik OAuth'unu kullanamaz → setup-token ile üretilen uzun-ömürlü
  // token'ı env'e enjekte et (config.claudeOAuthToken, ~/.claude-remote'ta, repo dışı).
  const env = { ...process.env };
  try {
    const cfg = config.load();
    if (cfg && cfg.claudeOAuthToken) env.CLAUDE_CODE_OAUTH_TOKEN = cfg.claudeOAuthToken;
  } catch { /* config yok */ }

  let proc;
  try {
    proc = spawn('cmd.exe', args, { cwd, env, windowsHide: true });
  } catch (e) {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'shrimp_error', text: e.message }));
    ws.close(); return;
  }

  let sessionId = null, firstPrompt = null;
  let buf = '';
  const outDec = new StringDecoder('utf8');   // çok-baytlı UTF-8 chunk sınırında bozulmayı önler
  const errDec = new StringDecoder('utf8');
  proc.stdout.on('data', d => {
    buf += outDec.write(d);
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
      if (!line.trim()) continue;
      // oturum id'sini yakala → native-sessions.json'a kaydet (listeye düşsün)
      if (!sessionId && line.indexOf('"session_id"') !== -1) {
        try { const o = JSON.parse(line); if (o.session_id) { sessionId = o.session_id; recordNative(sessionId, cwd, firstPrompt); } } catch { /* geç */ }
      }
      if (ws.readyState === 1) ws.send(line);   // ham JSON event
    }
  });
  proc.stderr.on('data', d => {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'shrimp_stderr', text: errDec.write(d) }));
  });
  proc.on('exit', code => {
    if (ws.readyState === 1) { ws.send(JSON.stringify({ type: 'shrimp_exit', code })); ws.close(1000, 'exit'); }
  });
  proc.on('error', e => {
    if (ws.readyState === 1) { ws.send(JSON.stringify({ type: 'shrimp_error', text: e.message })); ws.close(); }
  });

  ws.on('message', (data, isBinary) => {
    if (isBinary) return;
    let m; try { m = JSON.parse(data.toString()); } catch { return; }
    if (m.type === 'prompt' && typeof m.text === 'string') {
      if (firstPrompt === null) firstPrompt = m.text;
      if (sessionId) recordNative(sessionId, cwd, firstPrompt);   // başlık + aktiflik güncelle
      const msg = { type: 'user', message: { role: 'user', content: [{ type: 'text', text: m.text }] } };
      try { proc.stdin.write(JSON.stringify(msg) + '\n'); } catch { /* kapalı */ }
    }
  });
  // ws kapanınca claude'u öldür — Windows'ta cmd.exe /c torununu (asıl claude) de
  // öldürmek için AĞAÇ olarak sonlandır (taskkill /T), yoksa claude arka planda
  // token yakıp araç çalıştırmaya devam eder.
  ws.on('close', () => {
    try {
      if (process.platform === 'win32' && proc.pid) {
        spawn('taskkill', ['/pid', String(proc.pid), '/T', '/F'], { windowsHide: true }).on('error', () => {});
      } else {
        proc.kill();
      }
    } catch { /* zaten ölü */ }
  });
}

module.exports = { attach };
