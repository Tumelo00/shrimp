'use strict';
const os = require('os');
const { execFile } = require('child_process');

class Stats {
  constructor(cfg, extraFn) {
    this.cfg = cfg;
    this.extraFn = extraFn || (() => ({}));
    this.prevCpus = os.cpus();
    this.lastCpuAt = Date.now();
    this.lastCpuVal = 0;
    this.disks = [];
    this.diskAt = 0;
    this.diskPending = false;
    this.subs = new Set();
    this.timer = null;
    this._refreshDisks();
  }

  _cpuPercent() {
    const now = Date.now();
    if (now - this.lastCpuAt < 200) return this.lastCpuVal; // çok sık çağrıda son değeri ver
    const cur = os.cpus();
    let idle = 0, total = 0;
    for (let i = 0; i < cur.length; i++) {
      const c = cur[i].times, p = (this.prevCpus[i] || cur[i]).times;
      for (const k of Object.keys(c)) total += c[k] - p[k];
      idle += c.idle - p.idle;
    }
    this.prevCpus = cur;
    this.lastCpuAt = now;
    this.lastCpuVal = total > 0 ? Math.round((1 - idle / total) * 1000) / 10 : 0;
    return this.lastCpuVal;
  }

  _refreshDisks() {
    if (this.diskPending) return;
    if (Date.now() - this.diskAt < this.cfg.diskRefreshMs) return;
    this.diskPending = true;
    execFile('powershell.exe', [
      '-NoProfile', '-Command',
      "Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,Size,FreeSpace | ConvertTo-Json -Compress",
    ], { timeout: 10000 }, (err, stdout) => {
      this.diskPending = false;
      this.diskAt = Date.now();
      if (err) return;
      try {
        let arr = JSON.parse(stdout.trim());
        if (!Array.isArray(arr)) arr = [arr];
        this.disks = arr.map(d => ({
          drive: d.DeviceID,
          total: Number(d.Size) || 0,
          free: Number(d.FreeSpace) || 0,
        }));
      } catch { /* bozuk çıktı, eski değer kalsın */ }
    });
  }

  snapshot() {
    this._refreshDisks();
    return {
      cpu: this._cpuPercent(),
      memTotal: os.totalmem(),
      memFree: os.freemem(),
      uptime: os.uptime(),
      hostname: os.hostname(),
      disks: this.disks,
      ...this.extraFn(),
    };
  }

  subscribe(ws) {
    this.subs.add(ws);
    ws.on('close', () => {
      this.subs.delete(ws);
      if (!this.subs.size && this.timer) { clearInterval(this.timer); this.timer = null; }
    });
    try { ws.send(JSON.stringify(this.snapshot())); } catch { /* kapalı */ }
    if (!this.timer) {
      this.timer = setInterval(() => {
        const j = JSON.stringify(this.snapshot());
        for (const s of this.subs) { if (s.readyState === 1) s.send(j); }
      }, this.cfg.statsIntervalMs);
    }
  }
}

module.exports = { Stats };
