'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const CONFIG_DIR = path.join(os.homedir(), '.claude-remote');
const CONFIG_PATH = path.join(CONFIG_DIR, 'config.json');
const STATE_DIR = path.join(CONFIG_DIR, 'state');

const DEFAULTS = {
  port: 8787,
  host: 'auto',              // 'auto' = Tailscale IP, yoksa 127.0.0.1
  graceMs: 60000,            // son istemci koptuktan sonra kaydet+durdur beklemesi
  scrollbackBytes: 512 * 1024,
  statsIntervalMs: 2000,
  diskRefreshMs: 30000,
  fileRoots: ['C:\\'],
  maxFileReadBytes: 512 * 1024,
  usageLimit: 8000000,       // 5 saatlik pencere token limiti (yüzde için; planına göre ayarla)
};

// Atomik yaz: tmp'e yaz + rename (aynı disk → atomik). Kesinti anında yarım/bozuk
// config bırakmaz (yoksa parse hatası → yeni token üretilir → Mac kilitlenir).
function writeAtomic(file, data) {
  const tmp = `${file}.${process.pid}.tmp`;
  try { fs.writeFileSync(tmp, data); fs.renameSync(tmp, file); }
  catch { try { fs.writeFileSync(file, data); } catch { /* geç */ } }
}

function load() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  let cfg = {};
  let parsed = false;
  try { cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); parsed = true; } catch { /* ilk çalıştırma / bozuk */ }
  const merged = { ...DEFAULTS, ...cfg };
  let changed = false;
  if (!merged.token) { merged.token = crypto.randomBytes(24).toString('hex'); changed = true; }
  // Sadece yeni token üretildiyse ya da dosya hiç okunamadıysa yaz — her load'da
  // gereksiz (ve kesintide riskli) yeniden-yazmayı önle.
  if (changed || !parsed) writeAtomic(CONFIG_PATH, JSON.stringify(merged, null, 2));
  return merged;
}

function tailscaleIP() {
  const candidates = ['C:\\Program Files\\Tailscale\\tailscale.exe', 'tailscale'];
  for (const exe of candidates) {
    try {
      const out = execFileSync(exe, ['ip', '-4'], { timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] })
        .toString().trim().split(/\r?\n/)[0];
      if (/^100\./.test(out)) return out;
    } catch { /* sıradakini dene */ }
  }
  return null;
}

function resolveHost(cfg) {
  if (cfg.host !== 'auto') return cfg.host;
  return tailscaleIP() || '127.0.0.1';
}

module.exports = { load, resolveHost, tailscaleIP, CONFIG_DIR, CONFIG_PATH, STATE_DIR };
