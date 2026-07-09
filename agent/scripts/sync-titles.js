'use strict';
// Claude Desktop oturum verisini (başlık, cwd, pinned, son aktivite) okuyup
//   ~/.claude-remote/desktop-titles.json   (id → title, chat.js için)
//   ~/.claude-remote/desktop-sessions.json (düz liste: Recents + Pinned, Mac sidebar için)
// yazar. KULLANICI bağlamında çalışmalı (S4U servis Desktop klasörüne erişemez).
// Logon'da + saatte bir çalışır.
const fs = require('fs');
const path = require('path');
const os = require('os');

const APPDATA = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
const sessDir = path.join(APPDATA, 'Claude', 'claude-code-sessions');
const lsDir = path.join(APPDATA, 'Claude', 'Local Storage', 'leveldb');
const projectsDir = path.join(os.homedir(), '.claude', 'projects');
const outDir = path.join(os.homedir(), '.claude-remote');

// --- 1) Pinlenen oturum UUID'leri (leveldb 'pinnedOrder') ---
function pinnedIds() {
  const set = new Set();
  let files = [];
  try { files = fs.readdirSync(lsDir).filter(f => /\.(ldb|log)$/.test(f)); } catch { return set; }
  let bestArr = null;
  for (const f of files) {
    let s; try { s = fs.readFileSync(path.join(lsDir, f)).toString('latin1'); } catch { continue; }
    let i = s.lastIndexOf('pinnedOrder');
    while (i !== -1) {
      const seg = s.slice(i, i + 3000);
      const ids = (seg.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g)) || [];
      if (ids.length && (!bestArr || ids.length > bestArr.length)) bestArr = ids;
      i = s.lastIndexOf('pinnedOrder', i - 1);
    }
  }
  (bestArr || []).forEach(id => set.add(id));
  return set;
}

// --- 2) cliSessionId → proje slug (hangi ~/.claude/projects/<slug>/<id>.jsonl) ---
function slugMap() {
  const map = {};
  let dirs = [];
  try { dirs = fs.readdirSync(projectsDir); } catch { return map; }
  for (const slug of dirs) {
    let list; try { list = fs.readdirSync(path.join(projectsDir, slug)); } catch { continue; }
    for (const f of list) if (f.endsWith('.jsonl')) map[f.replace(/\.jsonl$/, '')] = slug;
  }
  return map;
}

// --- 3) local_*.json tara ---
const pins = pinnedIds();
const slugs = slugMap();
const titles = {};
const sessions = [];
const stack = [sessDir];
let scanned = 0;
while (stack.length && scanned < 50000) {
  const d = stack.pop();
  let entries; try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { continue; }
  for (const e of entries) {
    const full = path.join(d, e.name);
    if (e.isDirectory()) { stack.push(full); continue; }
    if (!e.name.startsWith('local_') || !e.name.endsWith('.json')) continue;
    scanned++;
    let o; try { o = JSON.parse(fs.readFileSync(full, 'utf8')); } catch { continue; }
    if (!o.cliSessionId || !o.title) continue;
    if (o.isArchived) continue;
    titles[o.cliSessionId] = o.title;
    const localUuid = String(o.sessionId || '').replace('local_', '');
    const pinned = pins.has(o.cliSessionId) || pins.has(localUuid);
    sessions.push({
      id: o.cliSessionId,
      title: o.title,
      cwd: o.cwd || '',
      slug: slugs[o.cliSessionId] || null,
      lastActivityAt: o.lastActivityAt || o.createdAt || 0,
      pinned,
    });
  }
}
sessions.sort((a, b) => (b.lastActivityAt || 0) - (a.lastActivityAt || 0));
// pinned hepsi + son 200 recent
const pinnedList = sessions.filter(s => s.pinned);
const recents = sessions.slice(0, 200);
const outList = [...pinnedList, ...recents.filter(s => !s.pinned)];

try {
  fs.mkdirSync(outDir, { recursive: true });
  const tCount = Object.keys(titles).length;
  // Güvenlik: hiç başlık yoksa (erişilemeyen bağlam) mevcut dolu dosyaları EZME.
  if (tCount === 0) {
    let ex = 0; try { ex = Object.keys(JSON.parse(fs.readFileSync(path.join(outDir, 'desktop-titles.json'), 'utf8'))).length; } catch {}
    if (ex > 0) { console.log(`0 bulundu; mevcut ${ex} korundu`); process.exit(0); }
  }
  fs.writeFileSync(path.join(outDir, 'desktop-titles.json'), JSON.stringify(titles));
  fs.writeFileSync(path.join(outDir, 'desktop-sessions.json'), JSON.stringify(outList));
  console.log(`${tCount} başlık, ${outList.length} oturum (${pinnedList.length} pinned) yazıldı`);
} catch (e) {
  console.error('yazılamadı:', e.message);
}
