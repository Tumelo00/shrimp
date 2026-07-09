'use strict';
// Kendini-iyileştiren watchdog: agent'ın sağlığını kontrol eder; yanıt vermezse
// takılı node'u öldürüp ClaudeRemoteAgent görevini yeniden başlatır.
// ClaudeRemoteWatchdog görevi bunu birkaç dakikada bir çalıştırır (S4U, Highest).
const http = require('http');
const { execFile } = require('child_process');

const PORT = 8787;
const HOSTS = ['127.0.0.1', 'localhost']; // agent Tailscale IP'ye bind olsa da localhost'tan da denenir
// Not: agent Tailscale IP'ye bind olur; ama 0.0.0.0 fallback'te localhost çalışır.
// Güvenli olması için Tailscale IP'yi de dene.

function check(host) {
  return new Promise((resolve) => {
    const req = http.get({ host, port: PORT, path: '/api/health', timeout: 4000 }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d.includes('"ok":true')));
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

async function tailscaleIP() {
  return new Promise((resolve) => {
    execFile('C:\\Program Files\\Tailscale\\tailscale.exe', ['ip', '-4'], { timeout: 4000 }, (e, out) => {
      if (e) return resolve(null);
      const ip = String(out).trim().split(/\r?\n/)[0];
      resolve(/^100\./.test(ip) ? ip : null);
    });
  });
}

function restartAgent() {
  return new Promise((resolve) => {
    // takılı node'ları öldür + görevi başlat (bu script Highest bağlamda çalışır)
    const ps = `Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' -and $_.ProcessId -ne ${process.pid} } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1; Start-ScheduledTask -TaskName ClaudeRemoteAgent`;
    execFile('powershell.exe', ['-NoProfile', '-Command', ps], { timeout: 15000 }, () => resolve());
  });
}

(async () => {
  const tsIp = await tailscaleIP();
  const hosts = tsIp ? [tsIp, ...HOSTS] : HOSTS;
  for (const h of hosts) {
    if (await check(h)) { console.log('agent saglikli:', h); process.exit(0); }
  }
  console.log('agent yanit vermiyor → yeniden baslatiliyor');
  await restartAgent();
  process.exit(0);
})();
