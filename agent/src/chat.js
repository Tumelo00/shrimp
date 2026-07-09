'use strict';
// ~/.claude/projects altındaki Claude Code oturum JSONL'lerini tembel okur.
const fs = require('fs');
const path = require('path');
const os = require('os');

const PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');
const HEAD_BYTES = 64 * 1024;

// Claude Desktop, Claude Code oturumları için AI başlıkları burada tutuyor:
//   %APPDATA%\Claude\claude-code-sessions\**\local_*.json  → {cliSessionId, title}
// S4U/servis bağlamında env farklı olabilir → birkaç konumu dene.
function desktopSessionsDir() {
  const cands = [];
  // os.homedir() ~/.claude'da çalışıyor → onu öncele (S4U'da env değişkenleri şaşabilir)
  cands.push(path.join(os.homedir(), 'AppData', 'Roaming', 'Claude', 'claude-code-sessions'));
  if (process.env.APPDATA) cands.push(path.join(process.env.APPDATA, 'Claude', 'claude-code-sessions'));
  if (process.env.USERPROFILE) cands.push(path.join(process.env.USERPROFILE, 'AppData', 'Roaming', 'Claude', 'claude-code-sessions'));
  for (const c of cands) { try { if (fs.existsSync(c)) return c; } catch { /* geç */ } }
  return cands[0];
}
const DESKTOP_SESSIONS = desktopSessionsDir();

const summaryCache = new Map(); // dosya -> {mtimeMs, summary}
const cwdCache = new Map();     // projeDizini -> {mtimeMs, cwd}
const chatCache = new Map();    // dosya -> {mtimeMs, messages}  (LRU, max 8)
let titleIndex = { at: 0, map: new Map() };  // cliSessionId -> title
const TITLE_TTL = 30 * 1000;

// Claude Desktop AI başlıkları (cliSessionId → title).
// Öncelik: sync-titles.js'in yazdığı ~/.claude-remote/desktop-titles.json (S4U servis
// bunu okuyabilir). Yoksa Desktop klasörünü doğrudan tara (kullanıcı bağlamında çalışır).
const TITLES_JSON = path.join(os.homedir(), '.claude-remote', 'desktop-titles.json');
function desktopTitles() {
  const now = Date.now();
  if (now - titleIndex.at < TITLE_TTL) return titleIndex.map;
  const map = new Map();
  // 1) senkronize edilmiş JSON (servis bağlamında da erişilebilir)
  try {
    const obj = JSON.parse(fs.readFileSync(TITLES_JSON, 'utf8'));
    for (const [k, v] of Object.entries(obj)) if (v) map.set(k, v);
  } catch { /* yok */ }
  // 2) doğrudan Desktop klasörü (kullanıcı bağlamındaysa)
  if (map.size === 0) {
    const stack = [DESKTOP_SESSIONS];
    let scanned = 0;
    while (stack.length && scanned < 20000) {
      const dir = stack.pop();
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) { stack.push(full); continue; }
        if (!e.name.startsWith('local_') || !e.name.endsWith('.json')) continue;
        scanned++;
        try {
          const o = JSON.parse(fs.readFileSync(full, 'utf8'));
          if (o.cliSessionId && o.title) map.set(o.cliSessionId, o.title);
        } catch { /* geç */ }
      }
    }
  }
  titleIndex = { at: now, map };
  return map;
}

function readHead(file, bytes = HEAD_BYTES) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(bytes);
    const n = fs.readSync(fd, buf, 0, bytes, 0);
    return buf.subarray(0, n).toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
}

function headObjects(file) {
  const out = [];
  for (const line of readHead(file).split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try { out.push(JSON.parse(t)); } catch { /* kesik son satır olabilir */ }
  }
  return out;
}

function textOf(message) {
  const c = message && message.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    const parts = [];
    for (const b of c) {
      if (!b || typeof b !== 'object') continue;
      if (b.type === 'text' && b.text) parts.push(b.text);
      else if (b.type === 'tool_use') parts.push(formatTool(b));
      // tool_result ve thinking blokları sohbet görünümüne alınmaz
    }
    return parts.join('\n');
  }
  return '';
}

// Araç kullanımını okunur bloğa çevir (hangi dosya, ne değişti).
function clip(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) + '…' : s; }
function miniDiff(oldS, newS) {
  const o = String(oldS == null ? '' : oldS).split('\n');
  const n = String(newS == null ? '' : newS).split('\n');
  const lines = [];
  for (const l of o.slice(0, 8)) lines.push('- ' + clip(l, 88));
  for (const l of n.slice(0, 8)) lines.push('+ ' + clip(l, 88));
  if (o.length > 8 || n.length > 8) lines.push('…');
  return lines.join('\n');
}
function formatTool(b) {
  const i = b.input || {};
  const name = b.name || 'araç';
  switch (name) {
    case 'Edit':
      return `✎ Düzenlendi: ${i.file_path || ''}\n${miniDiff(i.old_string, i.new_string)}`;
    case 'MultiEdit': {
      const edits = Array.isArray(i.edits) ? i.edits : [];
      const body = edits.slice(0, 4).map(e => miniDiff(e.old_string, e.new_string)).join('\n');
      return `✎ Çoklu düzenleme: ${i.file_path || ''} (${edits.length} değişiklik)\n${body}`;
    }
    case 'Write':
      return `＋ Yazıldı: ${i.file_path || ''}` +
             (i.content ? ` (${String(i.content).split('\n').length} satır)` : '');
    case 'NotebookEdit':
      return `✎ Notebook düzenlendi: ${i.notebook_path || ''}`;
    case 'Bash':
      return `$ ${clip(i.command, 200)}`;
    case 'Read':
      return `👁 Okundu: ${i.file_path || ''}`;
    case 'Grep':
      return `🔎 Arandı: ${clip(i.pattern, 80)}` + (i.path ? ` (${i.path})` : '');
    case 'Glob':
      return `🔎 ${clip(i.pattern, 80)}`;
    case 'TodoWrite':
      return `☑ Görev listesi güncellendi`;
    default: {
      const key = Object.keys(i)[0];
      return `⚙ ${name}` + (key ? `: ${clip(i[key], 80)}` : '');
    }
  }
}

function isNoise(text) {
  if (!text) return true;
  const t = text.trimStart();
  return t.startsWith('<command') || t.startsWith('<local-command') ||
         t.startsWith('Caveat:') || t.startsWith('<system-reminder');
}

function projectCwd(dir, newestFile) {
  const st = fs.statSync(newestFile);
  const hit = cwdCache.get(dir);
  if (hit && hit.mtimeMs === st.mtimeMs) return hit.cwd;
  let cwd = null;
  const m = readHead(newestFile, 16 * 1024).match(/"cwd":"((?:[^"\\]|\\.)*)"/);
  if (m) { try { cwd = JSON.parse('"' + m[1] + '"'); } catch { /* geç */ } }
  cwdCache.set(dir, { mtimeMs: st.mtimeMs, cwd });
  return cwd;
}

function listProjects() {
  if (!fs.existsSync(PROJECTS_DIR)) return [];
  const out = [];
  for (const dir of fs.readdirSync(PROJECTS_DIR)) {
    const full = path.join(PROJECTS_DIR, dir);
    let files;
    try { files = fs.readdirSync(full).filter(f => f.endsWith('.jsonl')); } catch { continue; }
    if (!files.length) continue;
    let last = 0, newest = null;
    for (const f of files) {
      let st;
      try { st = fs.statSync(path.join(full, f)); } catch { continue; }
      if (st.mtimeMs > last) { last = st.mtimeMs; newest = f; }
    }
    if (!newest) continue;
    let cwd = null;
    try { cwd = projectCwd(dir, path.join(full, newest)); } catch { /* geç */ }
    const name = (cwd && path.basename(cwd)) || cwd || dir;
    out.push({ dir, name, path: cwd || '', sessionCount: files.length, lastModified: Math.round(last) });
  }
  out.sort((a, b) => b.lastModified - a.lastModified);
  return out;
}

function sessionSummary(file) {
  const st = fs.statSync(file);
  const hit = summaryCache.get(file);
  if (hit && hit.mtimeMs === st.mtimeMs) return hit.summary;
  let summary = '';
  for (const obj of headObjects(file)) {
    if (obj.type === 'summary' && obj.summary) { summary = obj.summary; break; }
    if (obj.type === 'user' && obj.message && !obj.isMeta) {
      const t = textOf(obj.message);
      if (!isNoise(t)) { summary = t; break; }
    }
    if (obj.type === 'queue-operation' && obj.operation === 'enqueue' && typeof obj.content === 'string' && !isNoise(obj.content)) {
      summary = obj.content; break;
    }
  }
  summary = cleanTitle(summary);
  summaryCache.set(file, { mtimeMs: st.mtimeMs, summary });
  if (summaryCache.size > 500) summaryCache.delete(summaryCache.keys().next().value);
  return summary;
}

// Ham ilk-mesajı Claude Desktop tarzı kısa/temiz başlığa çevir.
function cleanTitle(raw) {
  let t = (raw || '').replace(/\s+/g, ' ').trim();
  // baştaki dolgu/hitap kelimelerini at
  const fillers = /^(kanka|kanki|abi|abicim|reis|moruk|lan|ya|kardeşim|dostum|hocam|selam|merhaba|slm)[\s,:]+/i;
  for (let i = 0; i < 3 && fillers.test(t); i++) t = t.replace(fillers, '');
  // ilk cümle veya ~64 karakter (kelime sınırında)
  const sentEnd = t.search(/[.!?\n]/);
  if (sentEnd > 12 && sentEnd < 80) t = t.slice(0, sentEnd);
  if (t.length > 64) {
    t = t.slice(0, 64);
    const sp = t.lastIndexOf(' ');
    if (sp > 30) t = t.slice(0, sp);
    t += '…';
  }
  t = t.trim();
  if (t) t = t.charAt(0).toLocaleUpperCase('tr') + t.slice(1);
  return t || 'Adsız sohbet';
}

function listSessions(projectDir) {
  if (!projectDir || projectDir.includes('..') || projectDir.includes(path.sep)) {
    throw new Error('geçersiz proje');
  }
  const full = path.join(PROJECTS_DIR, projectDir);
  const titles = desktopTitles();
  const out = [];
  for (const f of fs.readdirSync(full).filter(f => f.endsWith('.jsonl'))) {
    const file = path.join(full, f);
    let st;
    try { st = fs.statSync(file); } catch { continue; }
    const id = f.replace(/\.jsonl$/, '');
    // Öncelik: Claude Desktop'ın AI başlığı; yoksa ilk mesajdan temiz başlık.
    let summary = titles.get(id) || '';
    if (!summary) { try { summary = sessionSummary(file); } catch { /* geç */ } }
    out.push({ id, summary, mtime: Math.round(st.mtimeMs), size: st.size });
  }
  out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

const CHAT_MAX_BYTES = 12 * 1024 * 1024;   // çok büyük sohbetlerde son ~12MB okunur (bellek/hız)
function parseChat(file) {
  const st = fs.statSync(file);
  const hit = chatCache.get(file);
  if (hit && hit.mtimeMs === st.mtimeMs) {
    chatCache.delete(file); chatCache.set(file, hit);   // LRU: hit'te sona taşı
    return hit.messages;
  }
  let content;
  if (st.size > CHAT_MAX_BYTES) {
    const fd = fs.openSync(file, 'r');
    try {
      const buf = Buffer.alloc(CHAT_MAX_BYTES);
      fs.readSync(fd, buf, 0, CHAT_MAX_BYTES, st.size - CHAT_MAX_BYTES);
      content = buf.toString('utf8');
      const nl = content.indexOf('\n');            // ilk (yarım) satırı at
      if (nl >= 0) content = content.slice(nl + 1);
    } finally { fs.closeSync(fd); }
  } else {
    content = fs.readFileSync(file, 'utf8');
  }
  const messages = [];
  for (const line of content.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    let obj;
    try { obj = JSON.parse(t); } catch { continue; }
    if (obj.isMeta) continue;
    if (obj.type !== 'user' && obj.type !== 'assistant') continue;
    const text = textOf(obj.message);
    if (obj.type === 'user' && isNoise(text)) continue;
    if (!text.trim()) continue;
    messages.push({ role: obj.type, text, ts: obj.timestamp || '' });
  }
  chatCache.set(file, { mtimeMs: st.mtimeMs, messages });
  while (chatCache.size > 8) chatCache.delete(chatCache.keys().next().value);
  return messages;
}

function getChat(projectDir, id, limit = 60, before = null) {
  if (!projectDir || projectDir.includes('..') || projectDir.includes(path.sep)) throw new Error('geçersiz proje');
  if (!id || !/^[\w-]+$/.test(id)) throw new Error('geçersiz oturum');
  const file = path.join(PROJECTS_DIR, projectDir, id + '.jsonl');
  const messages = parseChat(file);
  const end = (before === null || before === undefined) ? messages.length : Math.max(0, Math.min(before, messages.length));
  const start = Math.max(0, end - limit);
  return { total: messages.length, start, messages: messages.slice(start, end) };
}

// Shrimp native chat oturumları (chatdriver.js kaydeder).
const NATIVE_JSON = path.join(os.homedir(), '.claude-remote', 'native-sessions.json');
function nativeSessions() {
  try {
    const o = JSON.parse(fs.readFileSync(NATIVE_JSON, 'utf8'));
    return o && typeof o === 'object' ? Object.values(o) : [];
  } catch { return []; }
}

// Bir oturum id'sinin JSONL dosyasını projeler altında bul (slug + mtime).
function findSessionFile(id) {
  if (!/^[\w-]+$/.test(id)) return null;
  let dirs;
  try { dirs = fs.readdirSync(PROJECTS_DIR); } catch { return null; }
  for (const dir of dirs) {
    const f = path.join(PROJECTS_DIR, dir, id + '.jsonl');
    let st; try { st = fs.statSync(f); } catch { continue; }
    return { slug: dir, mtime: st.mtimeMs, file: f };
  }
  return null;
}

// Claude Desktop tarzı DÜZ oturum listesi (Recents + pinned): Desktop mirror'ı +
// Shrimp native chat oturumları (böylece yeni açılan native sohbetler de listeye düşer).
function desktopSessions() {
  const p = path.join(os.homedir(), '.claude-remote', 'desktop-sessions.json');
  let list = [];
  try {
    const arr = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(arr)) list = arr;
  } catch { /* yok */ }

  const byId = new Map(list.map(s => [s.id, s]));
  const titles = desktopTitles();
  for (const n of nativeSessions()) {
    if (!n || !n.id || byId.has(n.id)) continue;   // Desktop zaten içeriyorsa atla
    const found = findSessionFile(n.id);
    let title = titles.get(n.id) || '';
    if (!title && found) { try { title = sessionSummary(found.file); } catch { /* geç */ } }
    if (!title) title = cleanTitle(n.title || '');
    const entry = {
      id: n.id,
      title: title || 'Adsız sohbet',
      cwd: n.cwd || '',
      slug: found ? found.slug : null,
      lastActivityAt: found ? Math.round(found.mtime) : (n.ts || 0),
      pinned: false,
    };
    list.push(entry);
    byId.set(n.id, entry);
  }
  list.sort((a, b) => (b.lastActivityAt || 0) - (a.lastActivityAt || 0));  // en yeni üstte
  return list;
}

// Bir proje dizininin gerçek çalışma yolunu (cwd) döndürür.
function projectPath(dir) {
  if (!dir || dir.includes('..') || dir.includes(path.sep)) return null;
  const full = path.join(PROJECTS_DIR, dir);
  let files;
  try { files = fs.readdirSync(full).filter(f => f.endsWith('.jsonl')); } catch { return null; }
  let last = 0, newest = null;
  for (const f of files) {
    let st; try { st = fs.statSync(path.join(full, f)); } catch { continue; }
    if (st.mtimeMs > last) { last = st.mtimeMs; newest = f; }
  }
  if (!newest) return null;
  try { return projectCwd(dir, path.join(full, newest)); } catch { return null; }
}

module.exports = { listProjects, listSessions, getChat, projectPath, desktopSessions, PROJECTS_DIR };
