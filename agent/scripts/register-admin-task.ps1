# Bir kez yukseltilmis kaydolur; sonra 'Start-ScheduledTask ShrimpAdmin' UAC SORMADAN calisir.
$me = "$env:USERDOMAIN\$env:USERNAME"
$dir = Join-Path $env:USERPROFILE '.claude-remote'
New-Item -ItemType Directory -Force $dir | Out-Null
$cmdFile = Join-Path $dir 'admin-cmd.ps1'
if (-not (Test-Path $cmdFile)) { Set-Content $cmdFile '# yonetici komutlari buraya yazilir' -Encoding UTF8 }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" + $cmdFile + "`"")
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName 'ShrimpAdmin' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Set-Content -Path "$env:TEMP\shrimp-admin-reg.txt" -Value "ShrimpAdmin kuruldu" -Encoding ASCII
