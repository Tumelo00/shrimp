# Agent'i PC ACILISINDA (boot) ve oturum acilisinda otomatik, gizli baslatir.
# S4U logon: kullanici oturumu olmadan da kullanici baglaminda calisir (WOL ile
# uzaktan acilista birinin login olmasina gerek kalmaz). Yonetici gerektirir.
$ErrorActionPreference = 'Stop'

$node = (Get-Command node).Source
$serverJs = (Resolve-Path (Join-Path $PSScriptRoot '..\src\server.js')).Path
$workDir = Split-Path $serverJs
$me = "$env:USERDOMAIN\$env:USERNAME"

# Konsol penceresi acilmasin diye VBS gizli baslatici
$vbsPath = Join-Path (Split-Path $PSScriptRoot) 'run-hidden.vbs'
$vbs = 'CreateObject("Wscript.Shell").Run """' + $node + '"" """ & """' + $serverJs + '""", 0, False'
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbsPath`"" -WorkingDirectory $workDir
# Hem boot hem logon (hangisi once olursa)
$trigBoot  = New-ScheduledTaskTrigger -AtStartup
$trigLogon = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable
# S4U: sifre saklamadan, kullanici baglaminda, oturum olmadan da calisir
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Highest

Register-ScheduledTask -TaskName 'ClaudeRemoteAgent' `
    -Action $action -Trigger @($trigBoot, $trigLogon) `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Tamam: 'ClaudeRemoteAgent' gorevi kuruldu (boot + logon, oturumsuz calisir)."

# --- Baslik senkron gorevi (INTERAKTIF: Claude Desktop klasorune erisim icin) ---
# S4U servis token'i Desktop'in Roaming klasorune erisemiyor; bu gorev kullanici
# oturumunda calisip basliklari ~/.claude-remote/desktop-titles.json'a yazar.
$syncJs = (Resolve-Path (Join-Path $PSScriptRoot 'sync-titles.js')).Path
$syncVbs = Join-Path (Split-Path $PSScriptRoot) 'sync-hidden.vbs'
$svbs = 'CreateObject("Wscript.Shell").Run """' + $node + '"" """ & """' + $syncJs + '""", 0, False'
Set-Content -Path $syncVbs -Value $svbs -Encoding ASCII
$syncAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$syncVbs`""
$syncTrigLogon = New-ScheduledTaskTrigger -AtLogOn
# 2 dakikada bir tazele (Desktop pin/başlık değişiklikleri canlı yansısın)
$syncTrigHourly = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2)
$syncPrincipal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive
$syncSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName 'ClaudeRemoteTitleSync' `
    -Action $syncAction -Trigger @($syncTrigLogon, $syncTrigHourly) `
    -Settings $syncSettings -Principal $syncPrincipal -Force | Out-Null
Write-Host "Tamam: 'ClaudeRemoteTitleSync' gorevi kuruldu (logon + saatlik, Desktop basliklari)."

# --- Watchdog gorevi (kendini-iyilestiren: agent olurse 3 dk'da geri baslatir) ---
$wdJs = (Resolve-Path (Join-Path $PSScriptRoot 'watchdog.js')).Path
$wdVbs = Join-Path (Split-Path $PSScriptRoot) 'wd-hidden.vbs'
$wvbs = 'CreateObject("Wscript.Shell").Run """' + $node + '"" """ & """' + $wdJs + '""", 0, False'
Set-Content -Path $wdVbs -Value $wvbs -Encoding ASCII
$wdAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$wdVbs`""
$wdTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 3)
$wdPrincipal = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Highest
$wdSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName 'ClaudeRemoteWatchdog' `
    -Action $wdAction -Trigger $wdTrigger -Principal $wdPrincipal -Settings $wdSettings -Force | Out-Null
Write-Host "Tamam: 'ClaudeRemoteWatchdog' gorevi kuruldu (3 dk'da bir saglik + oto-onarim)."
Write-Host "Hemen baslatmak icin: Start-ScheduledTask -TaskName ClaudeRemoteAgent"
