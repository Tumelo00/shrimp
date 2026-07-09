# Tum agent node'larini kesin oldur, port bosalana kadar, sonra gorevi baslat, pcinfo dogrula.
Enable-ScheduledTask -TaskName ClaudeRemoteAgent -ErrorAction SilentlyContinue | Out-Null
for ($i=0; $i -lt 8; $i++) {
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 700
  if (-not (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue)) { break }
}
Start-ScheduledTask -TaskName ClaudeRemoteAgent
Start-Sleep 5
try {
  $cfg = Get-Content "$env:USERPROFILE\.claude-remote\config.json" -Raw | ConvertFrom-Json
  $r = Invoke-RestMethod -Uri "http://100.88.55.115:8787/api/pcinfo" -Headers @{Authorization=("Bearer "+$cfg.token)} -TimeoutSec 8
  $out = "mac=$($r.mac) activeMac=$($r.activeMac) lanIP=$($r.lanIP)"
} catch { $out = "HATA: $($_.Exception.Message)" }
Set-Content -Path "$env:TEMP\pcinfo-result.txt" -Value $out -Encoding UTF8
