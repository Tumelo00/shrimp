# Tum agent node'larini ve port 8787 sahiplerini oldur (yukseltilmis calistir).
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
}
Start-Sleep 1
$n = (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
Set-Content -Path "$env:TEMP\kill-agent-result.txt" -Value "listen=$n" -Encoding ASCII
