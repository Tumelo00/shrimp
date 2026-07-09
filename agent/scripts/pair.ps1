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
function Publish { try { Invoke-WebRequest -Method Post -Uri "https://ntfy.sh/$topic" -Body $b64 -UseBasicParsing -TimeoutSec 8 | Out-Null } catch {} }
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

$btn = New-Object Windows.Forms.Button
$btn.Text = "Kopyala"; $btn.Size = New-Object Drawing.Size(150, 42)
$btn.Location = New-Object Drawing.Point(145, 185)
$btn.FlatStyle = 'Flat'; $btn.BackColor = [Drawing.Color]::FromArgb(60, 130, 246); $btn.ForeColor = [Drawing.Color]::White
$btn.Font = New-Object Drawing.Font("Segoe UI", 11)
$btn.Add_Click({ Set-Clipboard $code; $btn.Text = "Kopyalandi!" })
$form.Controls.Add($btn)

$lbl2 = New-Object Windows.Forms.Label
$lbl2.Text = "Bu pencere acik kalsin; Mac baglaninca kapatabilirsin."
$lbl2.ForeColor = [Drawing.Color]::Gray
$lbl2.Font = New-Object Drawing.Font("Segoe UI", 9)
$lbl2.AutoSize = $true; $lbl2.Location = New-Object Drawing.Point(70, 250)
$form.Controls.Add($lbl2)

# Mac subscribe olunca yakalasin diye periyodik yeniden yayinla
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 4000
$timer.Add_Tick({ Publish })
$timer.Start()

[void]$form.ShowDialog()
$timer.Stop()
