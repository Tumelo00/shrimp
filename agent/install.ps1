# Shrimp Agent — Windows tek-komut kurulum.
# YONETICI PowerShell'de calistir (otomatik baslatma gorevi icin admin gerekir):
#   irm https://raw.githubusercontent.com/Tumelo00/shrimp/main/agent/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$Repo = 'Tumelo00/shrimp'
$Dir  = Join-Path $env:LOCALAPPDATA 'ShrimpAgent'

Write-Host "`n=== Shrimp Agent Kurulumu ===`n" -ForegroundColor Cyan

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host "UYARI: Yonetici degilsin. Otomatik-baslatma gorevi kurulamaz." -ForegroundColor Yellow
  Write-Host "PowerShell'i SAG TIK > 'Yonetici olarak calistir' ile ac, komutu tekrar yapistir.`n" -ForegroundColor Yellow
}

# 1) Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "1) Node.js kuruluyor (winget)..." -ForegroundColor Cyan
  try { winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements | Out-Null } catch {}
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "Node.js kurulamadi. https://nodejs.org indir, tekrar dene." -ForegroundColor Red; return
}
Write-Host "   Node $(node -v)" -ForegroundColor Green

# 2) Gereklilik uyarilari
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "2) UYARI: Claude Code yok -> npm i -g @anthropic-ai/claude-code  (sonra 'claude' ile hesabinla giris yap)" -ForegroundColor Yellow
}
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue) -or (Test-Path 'C:\Program Files\Tailscale\tailscale.exe')
if (-not $ts) { Write-Host "   UYARI: Tailscale yok -> https://tailscale.com/download/windows  (Mac'in baglanabilmesi icin sart)" -ForegroundColor Yellow }

# 3) Agent'i indir
Write-Host "3) Agent indiriliyor (GitHub)..." -ForegroundColor Cyan
$zip = Join-Path $env:TEMP 'shrimp-agent.zip'
Invoke-WebRequest "https://github.com/$Repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
$tmp = Join-Path $env:TEMP ('shrimp-' + [guid]::NewGuid().ToString('N'))
Expand-Archive $zip $tmp -Force
# eski calisan agent'i durdur (8787 port cakismasi olmasin)
try { Get-ScheduledTask -TaskName ClaudeRemoteAgent -EA Stop | Stop-ScheduledTask -EA SilentlyContinue } catch {}
Get-NetTCPConnection -LocalPort 8787 -State Listen -EA SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue }
Start-Sleep 1
New-Item -ItemType Directory -Force $Dir | Out-Null
Copy-Item (Join-Path $tmp 'shrimp-main\agent\*') $Dir -Recurse -Force
Remove-Item $zip, $tmp -Recurse -Force -EA SilentlyContinue
Write-Host "   Kuruldu: $Dir" -ForegroundColor Green

# 4) Bagimliliklar
Write-Host "4) Bagimliliklar (npm install)..." -ForegroundColor Cyan
Push-Location $Dir
try { & npm install --no-audit --no-fund --omit=dev 2>&1 | Out-Null } finally { Pop-Location }

# 5) Otomatik-baslatma gorevleri + baslat
if ($admin) {
  Write-Host "5) Servis kaydediliyor + baslatiliyor..." -ForegroundColor Cyan
  & powershell -ExecutionPolicy Bypass -File (Join-Path $Dir 'scripts\install-task.ps1')
  Start-ScheduledTask -TaskName ClaudeRemoteAgent -EA SilentlyContinue
  Start-Sleep 3
} else {
  Write-Host "5) (Admin olmadigi icin otomatik-baslatma atlandi) Elle baslat: node `"$Dir\src\server.js`"" -ForegroundColor Yellow
  Start-Process node -ArgumentList "`"$Dir\src\server.js`"" -WindowStyle Hidden
  Start-Sleep 3
}

# 6) Eslestirme (6 haneli kod — GUI pencere + kopyala)
Write-Host "`nKurulum tamam! Eslestirme penceresi aciliyor (6 haneli kod)..." -ForegroundColor Green
& powershell -ExecutionPolicy Bypass -File (Join-Path $Dir 'scripts\pair.ps1')
Write-Host "Pencereyi tekrar acmak icin: powershell -ExecutionPolicy Bypass -File `"$Dir\scripts\pair.ps1`"" -ForegroundColor DarkGray
