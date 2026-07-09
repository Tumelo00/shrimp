Enable-ScheduledTask -TaskName ClaudeRemoteAgent -ErrorAction SilentlyContinue | Out-Null
Enable-ScheduledTask -TaskName ClaudeRemoteTitleSync -ErrorAction SilentlyContinue | Out-Null
Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep 1
Start-ScheduledTask -TaskName ClaudeRemoteAgent
Start-ScheduledTask -TaskName ClaudeRemoteTitleSync -ErrorAction SilentlyContinue
Start-Sleep 5
$n = (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
Set-Content -Path "$env:TEMP\start-service-result.txt" -Value "listen=$n" -Encoding ASCII
