'use strict';
// PC güç kontrolü (yeniden başlat / uyku / kapat) ve WOL için ağ bilgisi.
const os = require('os');
const { execFile, execFileSync } = require('child_process');

function primaryIface() {
  const ifaces = os.networkInterfaces();
  // LAN IPv4'ü (192.168/10./172.16-31) olan, internal olmayan ilk arayüz → WOL hedefi
  for (const [name, addrs] of Object.entries(ifaces)) {
    for (const a of addrs) {
      if (a.family === 'IPv4' && !a.internal &&
          /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(a.address)) {
        return { name, mac: a.mac, ip: a.address };
      }
    }
  }
  return { name: null, mac: null, ip: null };
}

// WOL için KALICI (donanım) MAC — PC kapalıyken NIC bunu dinler, spoof edileni değil.
// os.networkInterfaces() aktif (spoof olabilen) MAC'i verir; bu yüzden PowerShell'den al.
function permanentMac() {
  try {
    const out = execFileSync('powershell.exe', ['-NoProfile', '-Command',
      "(Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'} | Sort-Object -Property @{Expression={[uint64]$_.Speed}} -Descending | Select-Object -First 1).PermanentAddress"],
      { timeout: 6000, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    const hex = out.replace(/[-:]/g, '');
    if (/^[0-9A-Fa-f]{12}$/.test(hex)) {
      return hex.match(/.{2}/g).join(':').toUpperCase();
    }
  } catch { /* geç */ }
  return null;
}

function pcInfo() {
  const p = primaryIface();
  const permMac = permanentMac();
  return {
    hostname: os.hostname(),
    mac: permMac || p.mac,      // WOL: kalıcı MAC önceli
    activeMac: p.mac,           // bilgi amaçlı (spoof olabilir)
    lanIP: p.ip,
    iface: p.name,
  };
}

// Windows güç komutları
const ACTIONS = {
  restart: { file: 'shutdown.exe', args: ['/r', '/t', '5', '/c', 'Claude Remote: yeniden baslatiliyor'] },
  shutdown: { file: 'shutdown.exe', args: ['/s', '/t', '5', '/c', 'Claude Remote: kapatiliyor'] },
  sleep: { file: 'rundll32.exe', args: ['powrprof.dll,SetSuspendState', '0,1,0'] },
  cancel: { file: 'shutdown.exe', args: ['/a'] }, // planlı kapatmayı iptal
};

function power(action) {
  const a = ACTIONS[action];
  if (!a) throw new Error('gecersiz eylem: ' + action);
  return new Promise((resolve) => {
    execFile(a.file, a.args, { timeout: 8000 }, (err) => {
      // sleep hemen döner; restart/shutdown 5sn gecikmeli
      resolve({ ok: !err, action, error: err ? err.message : null });
    });
  });
}

module.exports = { pcInfo, power };
