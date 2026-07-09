$a = Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'} | Sort-Object LinkSpeed -Descending | Select-Object -First 1
$log = @()
try { Enable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop; $log += 'PowerManagement: acildi' } catch { $log += 'PM hata: '+$_.Exception.Message }
# standart registry keyword'leri (surucu dilinden bagimsiz)
foreach ($kw in @('*WakeOnMagicPacket','*WakeOnPattern')) {
  try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $kw -RegistryValue 1 -ErrorAction Stop; $log += "$kw = 1" } catch { $log += "$kw hata" }
}
# guc yonetimi: cihaz bilgisayari uyandirabilsin
try { powercfg /deviceenablewake "$($a.InterfaceDescription)" 2>&1 | Out-Null; $log += 'powercfg deviceenablewake ok' } catch {}
# durum
$pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
$log += 'WakeOnMagicPacket: ' + $pm.WakeOnMagicPacket
$log += 'PermanentMAC: ' + $a.PermanentAddress
Set-Content -Path "$env:TEMP\wol-result.txt" -Value ($log -join "`n") -Encoding UTF8
