# Shrimp Agent — yeniden baslat (YUKSELTILMIS calisir; tray UAC ile cagirir).
# Agent S4U/Highest (yukseltilmis) node surecidir; onu oldurmek yonetici gerektirir.
# ClaudeRemoteAgent gorevi node'u DETACHED baslattigi icin Stop-ScheduledTask onu
# oldurmez -> port 8787'yi dinleyen PID'i dogrudan oldur, sonra gorevi baslat.
$ErrorActionPreference = 'SilentlyContinue'
$port = 8787
$node = (Get-Command node).Source
if ($node) {
    $cfgDir = (Split-Path $PSScriptRoot) -replace '\\','/'
    $p = & $node -e "try{const c=require('$cfgDir/src/config').load();process.stdout.write(String(c.port||8787))}catch(e){process.stdout.write('8787')}" 2>$null
    if ($p -match '^\d+$') { $port = [int]$p }
}
# SADECE node surecini oldur — port'ta baska bir uygulama ( or. 127.0.0.1:8787 dev
# sunucusu) varsa ona dokunma. Agent zaten yalnizca Tailscale IP'sine bind oluyor.
Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue | ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -EA SilentlyContinue
    if ($proc -and $proc.ProcessName -eq 'node') { Stop-Process -Id $proc.Id -Force -EA SilentlyContinue }
}
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName ClaudeRemoteAgent -EA SilentlyContinue
