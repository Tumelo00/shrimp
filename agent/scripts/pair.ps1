# Shrimp — 6 haneli eslestirme kodu goster (GUI + kopyala) ve ntfy uzerinden Mac'e ilet.
# Kod kisadir (PC ekranindan Mac'e elle yazilir). Token tailnet-kilitli (host 100.x
# sadece kullanicinin tailnet'inde gecerli), ntfy sadece rendezvous.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$agentDir = (Split-Path $PSScriptRoot) -replace '\\','/'
$node = (Get-Command node).Source

# host/port/token
$j = & $node -e "const cfg=require('$agentDir/src/config'); const c=cfg.load(); const h=process.env.CLAUDE_REMOTE_HOST||cfg.resolveHost(c); process.stdout.write(JSON.stringify({host:h,port:c.port,token:c.token}))"
$info = $j | ConvertFrom-Json
if (-not $info.token) { [Windows.Forms.MessageBox]::Show("Agent yapilandirmasi bulunamadi. Once agent'i baslat."); return }

$code = -join ((1..6) | ForEach-Object { Get-Random -Maximum 10 })
$payload = "{""v"":1,""host"":""$($info.host)"",""port"":$($info.port),""token"":""$($info.token)""}"
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$topic = "shrimp-pair-$code"
# ntfy poll=1 cache'i mesaji ~12sa tutar -> Mac sonradan da cekebilir; tek yayin yeter,
# yine de ara ara tekrarla (sigorta). Kisa timeout: UI thread'i uzun bloklamasin.
function Publish { try { Invoke-WebRequest -Method Post -Uri "https://ntfy.sh/$topic" -Body $b64 -UseBasicParsing -TimeoutSec 4 | Out-Null } catch {} }
Publish

$form = New-Object Windows.Forms.Form
$form.Text = "Shrimp Eslestirme"
$form.Size = New-Object Drawing.Size(440, 340)
$form.StartPosition = "CenterScreen"
$form.BackColor = [Drawing.Color]::FromArgb(14, 22, 42)
$form.TopMost = $true

$lbl1 = New-Object Windows.Forms.Label
$lbl1.Text = "Mac'teki Shrimp sihirbazina bu kodu gir:"
$lbl1.ForeColor = [Drawing.Color]::White
$lbl1.Font = New-Object Drawing.Font("Segoe UI", 12)
$lbl1.AutoSize = $true; $lbl1.Location = New-Object Drawing.Point(50, 28)
$form.Controls.Add($lbl1)

$lblCode = New-Object Windows.Forms.Label
$lblCode.Text = ($code -replace '(\d{3})(\d{3})', '$1 $2')
$lblCode.ForeColor = [Drawing.Color]::FromArgb(80, 150, 255)
$lblCode.Font = New-Object Drawing.Font("Consolas", 46, [Drawing.FontStyle]::Bold)
$lblCode.AutoSize = $true; $lblCode.Location = New-Object Drawing.Point(90, 80)
$form.Controls.Add($lblCode)

$blue  = [Drawing.Color]::FromArgb(60, 130, 246)
$green = [Drawing.Color]::FromArgb(34, 172, 96)
$btn = New-Object Windows.Forms.Button
$btn.Text = "Kopyala"; $btn.Size = New-Object Drawing.Size(150, 42)
$btn.Location = New-Object Drawing.Point(145, 185)
$btn.FlatStyle = 'Flat'; $btn.FlatAppearance.BorderSize = 0
$btn.BackColor = $blue; $btn.ForeColor = [Drawing.Color]::White
$btn.Font = New-Object Drawing.Font("Segoe UI", 11)
# Kopyalama gorsel-geri-bildirimi: yesil flas + tik + 1.6sn sonra geri don
$revert = New-Object Windows.Forms.Timer
$revert.Interval = 1600
$revert.Add_Tick({ $revert.Stop(); $btn.Text = "Kopyala"; $btn.BackColor = $blue })
$btn.Add_Click({
    Set-Clipboard $code
    $btn.Text = [char]0x2713 + " Kopyalandi"
    $btn.BackColor = $green
    $revert.Stop(); $revert.Start()
})
$form.Controls.Add($btn)

$lbl2 = New-Object Windows.Forms.Label
$lbl2.Text = "Bu pencere acik kalsin; Mac baglaninca kapatabilirsin."
$lbl2.ForeColor = [Drawing.Color]::Gray
$lbl2.Font = New-Object Drawing.Font("Segoe UI", 9)
$lbl2.AutoSize = $true; $lbl2.Location = New-Object Drawing.Point(70, 250)
$form.Controls.Add($lbl2)

# Baglaninca oto-kapat. YENI bir baglanti bekle: acilistaki mevcut istemci sayisini baz al
# (zaten bagli bir Mac varken ikinci cihaz eslestirirken yanlis kapanmasin).
$healthUrl = "http://$($info.host):$($info.port)/api/health"
$script:baseClients = 0
try { $hb = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2; if ($hb.clients) { $script:baseClients = [int]$hb.clients } } catch {}
$closeTimer = New-Object Windows.Forms.Timer
$closeTimer.Interval = 1800
$closeTimer.Add_Tick({ $closeTimer.Stop(); $form.Close() })
$script:pt = 0
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    $script:pt++
    if ($script:pt % 5 -eq 0) { Publish }   # ~her 15sn'de bir sigorta yeniden-yayin
    try {
        $h = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ([int]$h.clients -gt $script:baseClients) {   # yalnizca YENI baglanti
            $lbl1.Text = "Mac baglandi!"; $lbl1.ForeColor = $green
            $lbl2.Text = "Baglanti kuruldu, bu pencere kapaniyor..."
            $timer.Stop(); $closeTimer.Start()
        }
    } catch {}
})
$timer.Start()

[void]$form.ShowDialog()
$timer.Stop()
