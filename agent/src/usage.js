'use strict';
// Claude Code token kullanımını ~/.claude/projects JSONL'lerinden toplar.
// Her assistant mesajındaki message.usage {input_tokens, output_tokens,
// cache_creation_input_tokens, cache_read_input_tokens} sayılır.
const fs = require('fs');
const path = require('path');
const os = require('os');

const PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');

// Fiyatlandırma (USD / 1M token) — kaba tahmin; model bazında yaklaşık.
const PRICE = { in: 3, out: 15, cacheWrite: 3.75, cacheRead: 0.30 };

let cache = { at: 0, data: null };
const TTL = 60 * 1000;
const fileCache = new Map();   // dosya -> {mtimeMs, agg}  (mtime değişmeyen dosya tekrar okunmaz)

// Abonelik planı (~/.claude/.credentials.json → claudeAiOauth.subscriptionType).
let planCache = { at: 0, label: '' };
function planLabel() {
  const now = Date.now();
  if (now - planCache.at < 5 * 60 * 1000) return planCache.label;
  let label = '';
  try {
    const raw = fs.readFileSync(path.join(os.homedir(), '.claude', '.credentials.json'), 'utf8');
    const j = JSON.parse(raw);
    const o = j.claudeAiOauth || {};
    const sub = String(o.subscriptionType || '').trim();
    const tier = String(o.rateLimitTier || '').trim();
    if (sub) {
      const nice = sub.charAt(0).toUpperCase() + sub.slice(1);       // max → Max
      const mult = /max/i.test(sub) ? (/20/.test(tier) ? ' (20x)' : ' (5x)') : '';
      label = nice + mult;
    }
  } catch { /* yok */ }
  planCache = { at: now, label };
  return label;
}

function dayKey(ts) {
  // ts ISO string → YYYY-MM-DD
  return typeof ts === 'string' && ts.length >= 10 ? ts.slice(0, 10) : 'bilinmeyen';
}

// Tek dosyayı parse edip özet çıkar (mtime cache'li). recent = son ~30 saatlik
// mesajların (ts, token) listesi → 5 saatlik pencere sorgu anında hesaplanır.
function parseFile(file) {
  let st;
  try { st = fs.statSync(file); } catch { return null; }
  const hit = fileCache.get(file);
  if (hit && hit.mtimeMs === st.mtimeMs) return hit.agg;
  const agg = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0, cost: 0, days: {}, recent: [] };
  const recentCut = Date.now() - 7.2 * 24 * 3600 * 1000;   // haftalık pencere için ~7 gün
  let content;
  try { content = fs.readFileSync(file, 'utf8'); } catch { return agg; }
  for (const line of content.split('\n')) {
    const t = line.trim();
    if (!t || t.indexOf('"usage"') === -1) continue;
    let obj; try { obj = JSON.parse(t); } catch { continue; }
    const u = obj.message && obj.message.usage;
    if (!u) continue;
    const inp = u.input_tokens || 0, out = u.output_tokens || 0;
    const cw = u.cache_creation_input_tokens || 0, cr = u.cache_read_input_tokens || 0;
    const cost = (inp * PRICE.in + out * PRICE.out + cw * PRICE.cacheWrite + cr * PRICE.cacheRead) / 1e6;
    const d = dayKey(obj.timestamp);
    const day = agg.days[d] || (agg.days[d] = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0, cost: 0 });
    day.input += inp; day.output += out; day.cacheWrite += cw; day.cacheRead += cr; day.messages++; day.cost += cost;
    agg.input += inp; agg.output += out; agg.cacheWrite += cw; agg.cacheRead += cr; agg.messages++; agg.cost += cost;
    const ts = obj.timestamp ? Date.parse(obj.timestamp) : NaN;
    if (!isNaN(ts) && ts >= recentCut) agg.recent.push({ ts, inp, out, cw, cr });
  }
  fileCache.set(file, { mtimeMs: st.mtimeMs, agg });
  return agg;
}

function scan(limitTokens) {
  const byDay = {};
  const totals = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0, cost: 0 };
  const now = Date.now();
  const windowMs = 5 * 3600 * 1000;
  const weekMs = 7 * 24 * 3600 * 1000;
  const window = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0 };
  const week = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0 };
  let oldest5 = Infinity, oldest7 = Infinity;   // penceredeki en eski mesaj → sıfırlanma anı
  let files = [];
  try {
    for (const dir of fs.readdirSync(PROJECTS_DIR)) {
      const full = path.join(PROJECTS_DIR, dir);
      let list;
      try { list = fs.readdirSync(full); } catch { continue; }
      for (const f of list) if (f.endsWith('.jsonl')) files.push(path.join(full, f));
    }
  } catch { /* dizin yok */ }

  const seen = new Set();
  for (const file of files) {
    seen.add(file);
    const agg = parseFile(file);       // mtime cache'li
    if (!agg) continue;
    totals.input += agg.input; totals.output += agg.output;
    totals.cacheWrite += agg.cacheWrite; totals.cacheRead += agg.cacheRead;
    totals.messages += agg.messages; totals.cost += agg.cost;
    for (const [d, v] of Object.entries(agg.days)) {
      const day = byDay[d] || (byDay[d] = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, messages: 0, cost: 0 });
      day.input += v.input; day.output += v.output; day.cacheWrite += v.cacheWrite;
      day.cacheRead += v.cacheRead; day.messages += v.messages; day.cost += v.cost;
    }
    for (const m of agg.recent) {
      if (now - m.ts <= windowMs) {
        window.input += m.inp; window.output += m.out; window.cacheWrite += m.cw; window.cacheRead += m.cr; window.messages++;
        if (m.ts < oldest5) oldest5 = m.ts;
      }
      if (now - m.ts <= weekMs) {
        week.input += m.inp; week.output += m.out; week.cacheWrite += m.cw; week.cacheRead += m.cr; week.messages++;
        if (m.ts < oldest7) oldest7 = m.ts;
      }
    }
  }
  // silinmiş dosyaları cache'ten temizle
  for (const k of fileCache.keys()) if (!seen.has(k)) fileCache.delete(k);

  const days = Object.entries(byDay)
    .map(([date, v]) => ({ date, ...v, cost: Math.round(v.cost * 100) / 100 }))
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 30);
  totals.cost = Math.round(totals.cost * 100) / 100;
  // yüzde = pencere içindeki "sayılan" token (input+output+cacheWrite; cacheRead ucuz, hariç) / limit
  const windowUsed = window.input + window.output + window.cacheWrite;
  const limit = limitTokens > 0 ? limitTokens : 8_000_000;
  const percent = Math.min(100, Math.round((windowUsed / limit) * 1000) / 10);
  // haftalık: kaba oran (5 saatlik limitin ~5 katı hacim varsayımı)
  const weekUsed = week.input + week.output + week.cacheWrite;
  const weekLimit = limit * 12;
  const weekPct = Math.min(100, Math.round((weekUsed / weekLimit) * 1000) / 10);
  const resetIn5 = oldest5 === Infinity ? 0 : Math.max(0, Math.round((oldest5 + windowMs - now) / 1000));
  const resetIn7 = oldest7 === Infinity ? 0 : Math.max(0, Math.round((oldest7 + weekMs - now) / 1000));
  return {
    totals, days, files: files.length,
    plan: planLabel(),
    window: { ...window, used: windowUsed, limit, percent, windowHours: 5, resetInSec: resetIn5 },
    weekly: { ...week, used: weekUsed, limit: weekLimit, percent: weekPct, resetInSec: resetIn7 },
  };
}

function usage(limitTokens) {
  const now = Date.now();
  if (cache.data && now - cache.at < TTL) return cache.data;
  const data = scan(limitTokens);
  cache = { at: now, data };
  return data;
}

module.exports = { usage };
