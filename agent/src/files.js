'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const MAX_ENTRIES = 2000;

// Gizli kimlik dizinleri — asla /api/file ile okunamaz (OAuth token, agent token burada).
const DENY = [path.join(os.homedir(), '.claude-remote'), path.join(os.homedir(), '.claude')]
  .map(d => path.resolve(d).toLowerCase());

// Symlink/junction ile kök-dışına kaçışı engelle: gerçek yolu çöz.
function realResolve(p) {
  try { return fs.realpathSync.native(p); } catch { return path.resolve(p); }
}

function withSep(s) { return s.endsWith(path.sep) ? s : s + path.sep; }

function isAllowed(p, roots) {
  const r = realResolve(p).toLowerCase();
  // gizli dizinleri reddet (kendisi veya altı)
  for (const d of DENY) { if (r === d || r.startsWith(withSep(d))) return false; }
  // yalnızca bir kökün İÇİNDE (sınır ayıracı zorunlu) olanlara izin ver
  return roots.some(root => {
    const rr = realResolve(root).toLowerCase();
    return r === rr || r.startsWith(withSep(rr));
  });
}

function listDir(p, cfg) {
  const resolved = path.resolve(p);
  if (!isAllowed(resolved, cfg.fileRoots)) throw new Error('erişime kapalı yol');
  const entries = [];
  const items = fs.readdirSync(resolved, { withFileTypes: true });
  for (const it of items) {
    if (entries.length >= MAX_ENTRIES) break;
    let size = 0, mtime = 0;
    if (!it.isDirectory()) {
      try {
        const st = fs.statSync(path.join(resolved, it.name));
        size = st.size; mtime = Math.round(st.mtimeMs);
      } catch { /* erişilemeyen dosya */ }
    }
    entries.push({ name: it.name, dir: it.isDirectory(), size, mtime });
  }
  entries.sort((a, b) => (b.dir - a.dir) || a.name.localeCompare(b.name, 'tr'));
  return { path: resolved, truncated: items.length > MAX_ENTRIES, entries };
}

function readFileSafe(p, cfg) {
  const resolved = path.resolve(p);
  if (!isAllowed(resolved, cfg.fileRoots)) throw new Error('erişime kapalı yol');
  const st = fs.statSync(resolved);
  const max = cfg.maxFileReadBytes;
  const fd = fs.openSync(resolved, 'r');
  let buf;
  try {
    buf = Buffer.alloc(Math.min(st.size, max));
    fs.readSync(fd, buf, 0, buf.length, 0);
  } finally {
    fs.closeSync(fd);
  }
  const probe = buf.subarray(0, 8192);
  if (probe.includes(0)) return { path: resolved, size: st.size, binary: true, content: '' };
  return { path: resolved, size: st.size, binary: false, truncated: st.size > max, content: buf.toString('utf8') };
}

module.exports = { listDir, readFileSafe };
