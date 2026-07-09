'use strict';
const http = require('http');
const url = require('url');
const { WebSocketServer } = require('ws');
const config = require('./config');
const chat = require('./chat');
const filesApi = require('./files');
const { Stats } = require('./stats');
const { TerminalManager } = require('./terminal');
const powerApi = require('./power');
const usageApi = require('./usage');
const chatDriver = require('./chatdriver');

const cfg = config.load();
const terminals = new TerminalManager(cfg, config.STATE_DIR);
const pcInfo = powerApi.pcInfo();
const stats = new Stats(cfg, () => ({ terminals: terminals.sessions.size, mac: pcInfo.mac, lanIP: pcInfo.lanIP }));

// ── Watchdog: istemci kalmayınca kaydet + durdur ──────────────────────────
const clients = new Set();
let graceTimer = null;

function clientCame(ws) {
  clients.add(ws);
  if (graceTimer) { clearTimeout(graceTimer); graceTimer = null; }
}

function clientGone(ws) {
  clients.delete(ws);
  if (clients.size) return;
  if (graceTimer) clearTimeout(graceTimer);
  console.log(`[watchdog] istemci kalmadı; ${Math.round(cfg.graceMs / 1000)}sn içinde dönen olmazsa kaydet+durdur`);
  graceTimer = setTimeout(() => {
    graceTimer = null;
    const n = terminals.saveAndStopAll('istemci-koptu');
    if (n) console.log(`[watchdog] ${n} terminal kaydedilip durduruldu`);
  }, cfg.graceMs);
}

// Terminal oluşturma isteğini normalleştir: proje→cwd, resume + model/mod/efor → claude args.
const PERMISSION_MODES = ['acceptEdits', 'auto', 'bypassPermissions', 'default', 'dontAsk', 'plan'];
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];
function resolveCreate(body) {
  const b = { ...body };
  if (b.project && !b.cwd) {
    const cwd = chat.projectPath(String(b.project));
    if (cwd) b.cwd = cwd;
  }
  const extra = [];
  if (b.resumeSession && /^[\w-]+$/.test(String(b.resumeSession))) {
    extra.push('--resume', String(b.resumeSession));
  }
  // model/mod/efor (spawn'a dizi olarak gider; shell injection yok)
  if (b.model && /^[\w.\-]{1,60}$/.test(String(b.model))) extra.push('--model', String(b.model));
  if (b.permissionMode && PERMISSION_MODES.includes(String(b.permissionMode))) extra.push('--permission-mode', String(b.permissionMode));
  if (b.effort && EFFORTS.includes(String(b.effort))) extra.push('--effort', String(b.effort));
  if (extra.length) {
    b.mode = 'claude';
    b.args = (Array.isArray(b.args) ? b.args : []).concat(extra);
  }
  return b;
}

// ── HTTP yardımcıları ─────────────────────────────────────────────────────
function json(res, code, obj) {
  const b = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(b),
  });
  res.end(b);
}

function auth(req, parsed) {
  const h = req.headers.authorization || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : parsed.query.token;
  return typeof t === 'string' && t.length > 0 && t === cfg.token;
}

function readBody(req, maxBytes = 1 << 20) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > maxBytes) { reject(new Error('gövde çok büyük')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); }
      catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

// Görsel/dosya yükleme: base64 → PC'de geçici dosya → yol döner (terminale eklenir).
const fs = require('fs');
const UPLOAD_DIR = require('path').join(config.CONFIG_DIR, 'uploads');
function handleUpload(body) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const raw = String(body.name || 'dosya').replace(/[^\w.\- ]/g, '_').slice(-60) || 'dosya';
  const name = `${Date.now()}_${raw}`;
  const p = require('path').join(UPLOAD_DIR, name);
  const data = Buffer.from(String(body.dataBase64 || ''), 'base64');
  if (!data.length) throw new Error('boş veri');
  fs.writeFileSync(p, data);
  // eski yüklemeleri temizle (>50)
  try {
    const files = fs.readdirSync(UPLOAD_DIR).map(f => ({ f, t: fs.statSync(require('path').join(UPLOAD_DIR, f)).mtimeMs }))
      .sort((a, b) => b.t - a.t);
    for (const { f } of files.slice(50)) fs.rmSync(require('path').join(UPLOAD_DIR, f), { force: true });
  } catch { /* geç */ }
  return { path: p, name };
}

// Native chat için Anthropic yetkilendirme: setup-token'ı PTY'de çalıştıran
// runner'ı spawn eder, durum dosyasını bekleyip sonucu döner (token config'e kaydedilir).
const { spawn: spawnProc } = require('child_process');
function handleSetupToken() {
  return new Promise((resolve) => {
    const runner = require('path').join(__dirname, '..', 'scripts', 'setup-token-runner.js');
    const statusFile = require('path').join(config.CONFIG_DIR, 'setup-token-status.json');
    try { fs.rmSync(statusFile, { force: true }); } catch { /* geç */ }
    let child;
    try { child = spawnProc(process.execPath, [runner], { stdio: 'ignore', env: process.env }); }
    catch (e) { return resolve({ ok: false, error: 'runner başlatılamadı: ' + e.message }); }
    child.on('error', () => resolve({ ok: false, error: 'runner hatası' }));
    const start = Date.now();
    const poll = setInterval(() => {
      let st = null;
      try { st = JSON.parse(fs.readFileSync(statusFile, 'utf8')); } catch { /* henüz yok */ }
      if (st && st.state && st.state !== 'running') { clearInterval(poll); resolve({ ok: !!st.ok, state: st.state, error: st.error || null }); }
      else if (Date.now() - start > 130000) { clearInterval(poll); try { child.kill(); } catch {} resolve({ ok: false, error: 'zaman aşımı' }); }
    }, 700);
  });
}

// ── Sunucu ────────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const parsed = url.parse(req.url, true);
  const p = parsed.pathname;
  if (p === '/api/health') return json(res, 200, { ok: true, name: 'claude-remote-agent', version: '0.1.0', hasClaudeToken: !!cfg.claudeOAuthToken });
  if (!auth(req, parsed)) return json(res, 401, { error: 'unauthorized' });
  try {
    if (req.method === 'GET') {
      if (p === '/api/projects') return json(res, 200, { projects: chat.listProjects() });
      if (p === '/api/sessions') return json(res, 200, { sessions: chat.listSessions(parsed.query.project) });
      if (p === '/api/desktop-sessions') return json(res, 200, { sessions: chat.desktopSessions() });
      if (p === '/api/chat') {
        return json(res, 200, chat.getChat(
          parsed.query.project, parsed.query.id,
          parseInt(parsed.query.limit, 10) || 60,
          parsed.query.before !== undefined ? parseInt(parsed.query.before, 10) : null,
        ));
      }
      if (p === '/api/files') return json(res, 200, filesApi.listDir(parsed.query.path || cfg.fileRoots[0], cfg));
      if (p === '/api/file') return json(res, 200, filesApi.readFileSafe(parsed.query.path, cfg));
      if (p === '/api/terminals') return json(res, 200, terminals.list());
      if (p === '/api/stats') return json(res, 200, stats.snapshot());
      if (p === '/api/pcinfo') return json(res, 200, pcInfo);
      if (p === '/api/usage') return json(res, 200, usageApi.usage(cfg.usageLimit));
    }
    if (req.method === 'POST') {
      if (p === '/api/terminals') return json(res, 200, terminals.create(resolveCreate(await readBody(req))));
      if (p === '/api/terminals/kill') { const b = await readBody(req); return json(res, 200, { ok: terminals.kill(String(b.id || '')) }); }
      if (p === '/api/save-stop') return json(res, 200, { saved: terminals.saveAndStopAll('manuel') });
      if (p === '/api/power') { const b = await readBody(req); return json(res, 200, await powerApi.power(String(b.action || ''))); }
      if (p === '/api/upload') { const b = await readBody(req, 20 << 20); return json(res, 200, handleUpload(b)); }
      if (p === '/api/setup-token') return json(res, 200, await handleSetupToken());
    }
    return json(res, 404, { error: 'not found' });
  } catch (e) {
    return json(res, 500, { error: e.message });
  }
});

const wss = new WebSocketServer({ noServer: true, perMessageDeflate: false });

server.on('upgrade', (req, socket, head) => {
  const parsed = url.parse(req.url, true);
  if (!auth(req, parsed)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, ws => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    clientCame(ws);
    ws.on('close', () => clientGone(ws));
    if (parsed.pathname === '/ws/terminal') {
      if (!terminals.attach(String(parsed.query.id || ''), ws)) ws.close(4004, 'terminal yok');
    } else if (parsed.pathname === '/ws/chat') {
      chatDriver.attach(ws, parsed.query);
    } else if (parsed.pathname === '/ws/stats') {
      stats.subscribe(ws);
    } else {
      ws.close(4000, 'bilinmeyen yol');
    }
  });
});

// Uyuyan/kopan istemcileri temizle ki watchdog takılı kalmasın
setInterval(() => {
  for (const ws of clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch { /* kapalı */ }
  }
}, 30000).unref();

// Kapanışta kaydet
let shuttingDown = false;
function shutdown(sig) {
  if (shuttingDown) return;
  shuttingDown = true;
  const n = terminals.saveAndStopAll(sig);
  console.log(`[${sig}] ${n} terminal kaydedildi, çıkılıyor`);
  process.exit(0);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// Dayanıklılık: yakalanmamış hata/promise agent'ı ÖLDÜRMESİN (app "bağlanılıyor"da kalmasın).
process.on('uncaughtException', (e) => { console.error('[uncaughtException]', e && e.stack || e); });
process.on('unhandledRejection', (e) => { console.error('[unhandledRejection]', e && (e.stack || e)); });

// ── Dinle ─────────────────────────────────────────────────────────────────
const host = process.env.CLAUDE_REMOTE_HOST || config.resolveHost(cfg);
const port = Number(process.env.CLAUDE_REMOTE_PORT) || cfg.port;
let bindRetries = 0;

server.on('error', err => {
  // Tailscale adresi boot'ta henüz bindlenebilir değilse (EADDRNOTAVAIL) birkaç kez
  // yeniden dene — asla 0.0.0.0'a (LAN'a) açılma (kapsam yalnızca tailnet/loopback).
  if (err.code === 'EADDRNOTAVAIL' && bindRetries < 15) {
    bindRetries++;
    console.error(`[uyarı] ${host}:${port} henüz bindlenemedi (${err.code}); 2sn sonra tekrar (${bindRetries}/15)`);
    setTimeout(() => server.listen(port, host), 2000);
    return;
  }
  console.error('[hata]', err.message);
  process.exit(1);
});

server.listen(port, host, () => {
  const a = server.address();
  console.log(`claude-remote-agent dinliyor: ${a.address}:${a.port}`);
  console.log(`token: ${cfg.token}`);
  console.log(`config: ${config.CONFIG_PATH}`);
  // usage cache'ini arka planda ısıt (ilk /api/usage isteği beklemesin);
  // henüz bağlı istemci yokken yapılır, per-file cache sonrasını hızlandırır.
  setTimeout(() => { try { usageApi.usage(cfg.usageLimit); } catch { /* geç */ } }, 1500);
});
