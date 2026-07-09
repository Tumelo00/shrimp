Disable-ScheduledTask -TaskName ClaudeRemoteAgent -ErrorAction SilentlyContinue | Out-Null
for ($i=0; $i -lt 4; $i++) {
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
  Start-Sleep 1
}
$n = (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
Set-Content -Path "$env:TEMP\stop-service-result.txt" -Value "listen=$n" -Encoding ASCII
