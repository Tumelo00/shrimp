'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const pty = require('@lydell/node-pty');

const FLUSH_MS = 16;           // çıktı birleştirme penceresi
const PAUSE_AT = 1 << 20;      // istemci WS tamponu 1MB'ı aşınca PTY duraklat
const RESUME_AT = 256 << 10;   // 256KB altına inince devam
const SAFE_SESSION_ID = /^[0-9a-f]{16}$/;   // crypto.randomBytes(8).toString('hex') biçimi

class TerminalManager {
  constructor(cfg, stateDir) {
    this.cfg = cfg;
    this.sessionsDir = path.join(stateDir, 'sessions');
    fs.mkdirSync(this.sessionsDir, { recursive: true });
    this.sessions = new Map();
  }

  list() {
    const active = [...this.sessions.values()].map(s => ({
      id: s.id, title: s.title, cwd: s.cwd, mode: s.mode,
      createdAt: s.createdAt, active: true, clients: s.clients.size,
    }));
    const saved = [];
    let dirs = [];
    try { dirs = fs.readdirSync(this.sessionsDir); } catch { /* yok */ }
    for (const dir of dirs) {
      try {
        const meta = JSON.parse(fs.readFileSync(path.join(this.sessionsDir, dir, 'meta.json'), 'utf8'));
        saved.push({ ...meta, active: false, clients: 0 });
      } catch { /* bozuk kayıt, atla */ }
    }
    saved.sort((a, b) => (b.savedAt || '').localeCompare(a.savedAt || ''));
    return { active, saved };
  }

  create(opts = {}) {
    let preload = null;
    if (opts.resumeSaved) {
      if (!SAFE_SESSION_ID.test(String(opts.resumeSaved))) throw new Error('geçersiz oturum kimliği');
      const dir = path.join(this.sessionsDir, opts.resumeSaved);
      const meta = JSON.parse(fs.readFileSync(path.join(dir, 'meta.json'), 'utf8'));
      opts.cwd = opts.cwd || meta.cwd;
      opts.mode = opts.mode || meta.mode;
      if (opts.mode !== 'shell' && !opts.args) opts.args = ['--continue'];
      try { preload = fs.readFileSync(path.join(dir, 'scrollback.bin')); } catch { /* yok */ }
      fs.rmSync(dir, { recursive: true, force: true });
    }

    const id = crypto.randomBytes(8).toString('hex');
    const cwd = opts.cwd && fs.existsSync(opts.cwd) ? opts.cwd : os.homedir();
    const cols = Math.max(20, opts.cols || 120);
    const rows = Math.max(5, opts.rows || 32);
    const mode = opts.mode === 'shell' ? 'shell' : 'claude';
    const extraArgs = Array.isArray(opts.args) ? opts.args.map(String) : [];

    let file, args;
    if (mode === 'shell') { file = 'powershell.exe'; args = ['-NoLogo']; }
    else { file = 'cmd.exe'; args = ['/c', 'claude', ...extraArgs]; }

    const proc = pty.spawn(file, args, {
      name: 'xterm-256color', cols, rows, cwd, env: process.env, useConpty: true,
    });

    const s = {
      id, pty: proc, cwd, mode, cols, rows,
      title: (mode === 'claude' ? 'claude · ' : 'shell · ') + (path.basename(cwd) || cwd),
      createdAt: new Date().toISOString(),
      clients: new Set(),
      ring: [], ringSize: 0,
      pending: [], flushTimer: null,
      paused: false, resumePoll: null,
      exited: false,
    };

    if (preload && preload.length) {
      this._pushRing(s, Buffer.concat([
        Buffer.from('\x1b[2m── önceki oturum kaydı ──\x1b[0m\r\n'),
        preload,
        Buffer.from('\r\n\x1b[2m── devam ediyor ──\x1b[0m\r\n'),
      ]));
    }

    proc.onData(d => this._onData(s, Buffer.from(d, 'utf8')));
    proc.onExit(({ exitCode }) => {
      s.exited = true;
      this._flush(s);
      this._broadcastJSON(s, { type: 'exit', code: exitCode });
      for (const ws of s.clients) { try { ws.close(1000, 'exit'); } catch { /* kapalı */ } }
      if (s.resumePoll) clearInterval(s.resumePoll);
      this.sessions.delete(id);
    });

    this.sessions.set(id, s);
    return { id, title: s.title, cwd: s.cwd, mode: s.mode };
  }

  _pushRing(s, buf) {
    s.ring.push(buf);
    s.ringSize += buf.length;
    while (s.ringSize > this.cfg.scrollbackBytes && s.ring.length > 1) {
      s.ringSize -= s.ring.shift().length;
    }
  }

  _onData(s, buf) {
    this._pushRing(s, buf);
    if (!s.clients.size) return; // izleyici yoksa yayın yok, sadece scrollback
    s.pending.push(buf);
    if (!s.flushTimer) s.flushTimer = setTimeout(() => this._flush(s), FLUSH_MS);
  }

  _flush(s) {
    if (s.flushTimer) { clearTimeout(s.flushTimer); s.flushTimer = null; }
    if (!s.pending.length) return;
    const chunk = s.pending.length === 1 ? s.pending[0] : Buffer.concat(s.pending);
    s.pending = [];
    let maxBuffered = 0;
    for (const ws of s.clients) {
      if (ws.readyState === 1) {
        ws.send(chunk, { binary: true });
        if (ws.bufferedAmount > maxBuffered) maxBuffered = ws.bufferedAmount;
      }
    }
    if (maxBuffered > PAUSE_AT && !s.paused) this._pause(s);
  }

  _pause(s) {
    s.paused = true;
    try { s.pty.pause(); } catch { /* desteklenmiyorsa geç */ }
    s.resumePoll = setInterval(() => {
      let max = 0;
      for (const ws of s.clients) if (ws.bufferedAmount > max) max = ws.bufferedAmount;
      if (max < RESUME_AT || !s.clients.size) {
        clearInterval(s.resumePoll);
        s.resumePoll = null;
        s.paused = false;
        try { s.pty.resume(); } catch { /* geç */ }
      }
    }, 50);
  }

  _broadcastJSON(s, obj) {
    const j = JSON.stringify(obj);
    for (const ws of s.clients) { if (ws.readyState === 1) ws.send(j); }
  }

  attach(id, ws) {
    const s = this.sessions.get(id);
    if (!s) return false;
    s.clients.add(ws);
    if (s.ringSize) ws.send(Buffer.concat(s.ring), { binary: true });
    ws.send(JSON.stringify({ type: 'title', title: s.title }));
    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        if (!s.exited) s.pty.write(data.toString('utf8'));
        return;
      }
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'resize' && msg.cols > 0 && msg.rows > 0) {
          s.cols = msg.cols; s.rows = msg.rows;
          if (!s.exited) s.pty.resize(msg.cols, msg.rows);
        }
      } catch { /* bozuk kontrol mesajı, yok say */ }
    });
    ws.on('close', () => s.clients.delete(ws));
    return true;
  }

  kill(id) {
    const s = this.sessions.get(id);
    if (s) { try { s.pty.kill(); } catch { /* zaten ölü */ } return true; }
    // kayıtlı (pasif) oturum olabilir — ama id path'e girmeden ÖNCE doğrula
    // (aksi halde "..\\.." ile sessionsDir dışında rmSync → rastgele silme).
    if (!SAFE_SESSION_ID.test(String(id))) return false;
    fs.rmSync(path.join(this.sessionsDir, id), { recursive: true, force: true });
    return true;
  }

  saveAndStopAll(reason) {
    let n = 0;
    for (const s of [...this.sessions.values()]) {
      try {
        const dir = path.join(this.sessionsDir, s.id);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'meta.json'), JSON.stringify({
          id: s.id, title: s.title, cwd: s.cwd, mode: s.mode,
          createdAt: s.createdAt, savedAt: new Date().toISOString(), reason,
        }, null, 2));
        fs.writeFileSync(path.join(dir, 'scrollback.bin'), Buffer.concat(s.ring));
        n++;
      } catch (e) {
        console.error('[terminal] kaydetme hatası', s.id, e.message);
      }
      if (s.resumePoll) clearInterval(s.resumePoll);
      if (s.flushTimer) clearTimeout(s.flushTimer);
      try { s.pty.kill(); } catch { /* zaten ölü */ }
      this.sessions.delete(s.id);
    }
    return n;
  }
}

module.exports = { TerminalManager };
