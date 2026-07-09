'use strict';
// `claude setup-token`'ı gerçek bir PTY'de çalıştırır (raw mode gerektirir),
// üretilen uzun-ömürlü token'ı (sk-ant-oat01-...) otomatik config.json'a kaydeder.
// Durum ~/.claude-remote/setup-token-status.json'a yazılır (endpoint bunu okur).
const pty = require('@lydell/node-pty');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DIR = path.join(os.homedir(), '.claude-remote');
const OUT = path.join(DIR, 'setup-token-out.log');
const STATUS = path.join(DIR, 'setup-token-status.json');
const CONFIG = path.join(DIR, 'config.json');
fs.mkdirSync(DIR, { recursive: true });

function writeAtomic(file, data) {
  const tmp = `${file}.${process.pid}.tmp`;
  try { fs.writeFileSync(tmp, data); fs.renameSync(tmp, file); }
  catch { try { fs.writeFileSync(file, data); } catch { /* geç */ } }
}
function setStatus(o) { try { writeAtomic(STATUS, JSON.stringify({ ...o, at: Date.now() })); } catch { /* geç */ } }

function saveToken(tok) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8')); } catch { /* yok */ }
  cfg.claudeOAuthToken = tok;
  writeAtomic(CONFIG, JSON.stringify(cfg, null, 2));
}

setStatus({ state: 'running' });
let buf = '';
let saved = false;

const p = pty.spawn('cmd.exe', ['/c', 'claude', 'setup-token'], {
  name: 'xterm-256color', cols: 100, rows: 30, cwd: os.homedir(), env: process.env,
});

function scan() {
  const m = buf.match(/sk-ant-oat01-[A-Za-z0-9_-]+/);
  if (m && !saved) {
    saved = true;
    try { saveToken(m[0]); setStatus({ state: 'done', ok: true }); } catch (e) { setStatus({ state: 'error', ok: false, error: String(e) }); }
  }
}

p.onData(d => {
  buf += d;
  if (buf.length > 200000) buf = buf.slice(-50000);
  try { fs.appendFileSync(OUT, d); } catch { /* geç */ }
  scan();
});

p.onExit(({ exitCode }) => {
  scan();
  if (!saved) setStatus({ state: 'error', ok: false, error: 'token bulunamadı (exit ' + exitCode + ')' });
  // gizli log'u temizle (token içerebilir)
  try { fs.rmSync(OUT, { force: true }); } catch { /* geç */ }
  process.exit(0);
});

// güvenlik: 120sn içinde bitmezse durum yaz ve çık
setTimeout(() => { if (!saved) setStatus({ state: 'error', ok: false, error: 'zaman aşımı' }); try { p.kill(); } catch {} }, 120000);
