# Shrimp Service — sifirdan kolay kurulum (Windows PC).
# Calistir:  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
$ErrorActionPreference = 'Stop'
$agentDir = Split-Path $PSScriptRoot
Write-Host "`n=== Shrimp Service Kurulumu ===`n" -ForegroundColor Cyan

function Check($name, $cmd, $hint) {
    $ok = $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
    if ($ok) { Write-Host "  [OK] $name" -ForegroundColor Green }
    else { Write-Host "  [EKSIK] $name — $hint" -ForegroundColor Yellow }
    return $ok
}

Write-Host "1) Gereksinimler kontrol ediliyor..."
$node = Check "Node.js" "node" "https://nodejs.org indir"
$claude = Check "Claude Code" "claude" "npm i -g @anthropic-ai/claude-code  (sonra: claude  -> giris yap)"
$ts = $null -ne (Get-Command tailscale -ErrorAction SilentlyContinue) -or (Test-Path 'C:\Program Files\Tailscale\tailscale.exe')
if ($ts) { Write-Host "  [OK] Tailscale" -ForegroundColor Green } else { Write-Host "  [EKSIK] Tailscale — https://tailscale.com/download" -ForegroundColor Yellow }

if (-not $node) { Write-Host "`nNode.js sart. Kurup tekrar calistir." -ForegroundColor Red; exit 1 }
if (-not $claude) { Write-Host "`nNot: Claude Code kurulu degil. Kurup 'claude' ile bir kez giris yapmalisin (kendi hesabin)." -ForegroundColor Yellow }

Write-Host "`n2) Bagimliliklar kuruluyor (npm install)..."
Push-Location $agentDir
try { & npm install --no-audit --no-fund | Out-Null; Write-Host "  [OK] npm install" -ForegroundColor Green }
finally { Pop-Location }

Write-Host "`n3) Token uretiliyor..."
# agent'i kisa sure calistirip token'i al
$p = Start-Process node -ArgumentList "`"$agentDir\src\server.js`"" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
$cfgPath = Join-Path $env:USERPROFILE '.claude-remote\config.json'
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
$token = '(bulunamadi)'
if (Test-Path $cfgPath) { $token = (Get-Content $cfgPath -Raw | ConvertFrom-Json).token }

# Tailscale IP
$tsIp = '(Tailscale kapali)'
try {
    $exe = if (Get-Command tailscale -ErrorAction SilentlyContinue) { 'tailscale' } else { 'C:\Program Files\Tailscale\tailscale.exe' }
    $ip = (& $exe ip -4 2>$null | Select-Object -First 1)
    if ($ip -match '^100\.') { $tsIp = $ip.Trim() }
} catch {}

Write-Host "`n4) Otomatik baslatma servisi (boot + logon)..."
try {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'install-task.ps1') | Out-Null
    Start-ScheduledTask -TaskName ClaudeRemoteAgent -ErrorAction SilentlyContinue
    Write-Host "  [OK] Servis kuruldu ve baslatildi" -ForegroundColor Green
} catch { Write-Host "  [UYARI] Servis kurulamadi (yonetici gerekebilir): $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host " MAC UYGULAMASINA (Shrimp) GIRECEGIN BILGILER:" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Tailscale IP : $tsIp"
Write-Host "  Port         : 8787"
Write-Host "  Token        : $token"
Write-Host "===============================================`n" -ForegroundColor Cyan
Write-Host "Not: Mac ve PC ayni Tailscale hesabinda olmali. Mac'te Shrimp.app'i acip bu bilgileri gir." -ForegroundColor Gray
