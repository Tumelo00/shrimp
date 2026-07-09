# Shrimp Agent — sistem tepsisi (tray) ikonu.
# Kullanicinin INTERAKTIF oturumunda calisir (S4U agent session-0'da tray gosteremez).
# Saglar: durum gorunurlugu (Mac bagli / bekliyor / kapali) + tek-tikla yeni eslestirme
# kodu + agent'i yeniden baslat. Bir baglanti sorununda kullanici buradan kod alir.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Tek-instance (birden fazla tray ikonu birikmesin) ---
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\ShrimpAgentTray', [ref]$createdNew)
if (-not $createdNew) { return }

$scripts = $PSScriptRoot
$agentDir = Split-Path $scripts
$icoPath  = Join-Path $agentDir 'assets\shrimp.ico'
$pairPs1  = Join-Path $scripts 'pair.ps1'
$restartPs1 = Join-Path $scripts 'restart-agent.ps1'
$repoUrl  = 'https://github.com/Tumelo00/shrimp'
$node = (Get-Command node).Source

# host/port'u coz (health icin; token gerekmez). Agent YALNIZCA Tailscale IP'sine bind
# olur; logon'da Tailscale henuz hazir degilse config 127.0.0.1 dondurur -> her basarisiz
# saglik yoklamasinda yeniden coz (tailscale ip ile de dene) ki IP hazir olunca duzelsin.
$script:agentHost = '127.0.0.1'
$script:agentPort = 8787
function Resolve-Agent {
    if ($node) {
        $j = & $node -e "const cfg=require('$($agentDir -replace '\\','/')/src/config'); const c=cfg.load(); const h=process.env.CLAUDE_REMOTE_HOST||cfg.resolveHost(c); process.stdout.write(JSON.stringify({host:h,port:c.port}))" 2>$null
        if ($j) { try { $o = $j | ConvertFrom-Json; if ($o.host) { $script:agentHost = $o.host }; if ($o.port) { $script:agentPort = $o.port } } catch {} }
    }
    # host hala loopback ise (config auto ama TS gec geldi) tailscale ip ile dene
    if ($script:agentHost -eq '127.0.0.1') {
        $tsExe = if (Test-Path 'C:\Program Files\Tailscale\tailscale.exe') { 'C:\Program Files\Tailscale\tailscale.exe' } else { 'tailscale' }
        try { $ip = (& $tsExe ip -4 2>$null | Select-Object -First 1); if ($ip -match '^100\.') { $script:agentHost = $ip.Trim() } } catch {}
    }
}
Resolve-Agent

# --- Ikon ---
$notify = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path $icoPath) { $notify.Icon = New-Object System.Drawing.Icon($icoPath) }
else { $notify.Icon = [System.Drawing.SystemIcons]::Application }
$notify.Text = 'Shrimp Agent'
$notify.Visible = $true

# --- Menu ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$hdr = $menu.Items.Add('Shrimp Agent'); $hdr.Enabled = $false
$hdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
# NOT: devre-disi ToolStripItem rengi gri'ye zorlanir -> etkin birak ki yesil/kirmizi
# durum rengi gorunsun (tiklaninca sadece menu kapanir, zararsiz).
$statusItem = $menu.Items.Add('Durum kontrol ediliyor...')
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miPair = $menu.Items.Add('Yeni eslestirme kodu goster')
$miPair.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$miPair.Add_Click({
    if (Test-Path $pairPs1) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$pairPs1
    }
})

$miRestart = $menu.Items.Add('Agent''i yeniden baslat')
$miRestart.Add_Click({
    $up = [bool](Get-NetTCPConnection -LocalPort $script:agentPort -State Listen -EA SilentlyContinue)
    if ($up) {
        # Agent calisiyor -> gercek yeniden baslat icin yukseltilmis node'u oldur+baslat (UAC)
        if (Test-Path $restartPs1) {
            Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$restartPs1
            $notify.ShowBalloonTip(3000, 'Shrimp', 'Agent yeniden baslatiliyor...', [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } else {
        # Agent kapali -> UAC'siz baslat yeter
        Start-ScheduledTask -TaskName ClaudeRemoteAgent -EA SilentlyContinue
        $notify.ShowBalloonTip(3000, 'Shrimp', 'Agent baslatiliyor...', [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

$miRepo = $menu.Items.Add('Repo / yardim (GitHub)')
$miRepo.Add_Click({ Start-Process $repoUrl })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miQuit = $menu.Items.Add('Cikis (tepsiden kaldir)')
$miQuit.Add_Click({
    $notify.Visible = $false; $notify.Dispose()
    $poll.Stop(); $poll.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$notify.ContextMenuStrip = $menu

# Cift-tik = hizli erisim: yeni eslestirme kodu
$notify.Add_MouseDoubleClick({ $miPair.PerformClick() })

# --- Durum yoklama ---
$green = [System.Drawing.Color]::FromArgb(34, 172, 96)
$gray  = [System.Drawing.Color]::FromArgb(120, 130, 150)
$red   = [System.Drawing.Color]::FromArgb(210, 70, 70)
# false ile basla: logon'da agent henuz baglanmadan ilk yoklama yanlis "baglanti kesildi"
# balonu gostermesin (yalnizca gercek up->down gecisinde uyar).
$script:lastUp = $false

function Update-Status {
    $up = [bool](Get-NetTCPConnection -LocalPort $script:agentPort -State Listen -EA SilentlyContinue)
    if (-not $up) {
        $statusItem.Text = [char]0x25CF + ' Agent kapali'
        $statusItem.ForeColor = $red
        $notify.Text = 'Shrimp Agent - kapali'
        if ($script:lastUp) { $notify.ShowBalloonTip(4000, 'Shrimp Agent durdu', 'Baglanti kesildi. Menuden "yeniden baslat" ile ac.', [System.Windows.Forms.ToolTipIcon]::Warning) }
        $script:lastUp = $false
        return
    }
    $script:lastUp = $true
    $clients = -1
    try { $h = Invoke-RestMethod -Uri "http://$($script:agentHost):$($script:agentPort)/api/health" -TimeoutSec 2; $clients = [int]$h.clients }
    catch { Resolve-Agent }   # host yanlis/eskiyse bir sonraki yoklama icin tazele
    if ($clients -ge 1) {
        $statusItem.Text = [char]0x25CF + ' Mac bagli'
        $statusItem.ForeColor = $green
        $notify.Text = 'Shrimp Agent - Mac bagli'
    } elseif ($clients -eq 0) {
        $statusItem.Text = [char]0x25CB + ' Hazir - Mac bekleniyor'
        $statusItem.ForeColor = $gray
        $notify.Text = 'Shrimp Agent - Mac bekleniyor'
    } else {
        $statusItem.Text = [char]0x25CF + ' Agent acik'
        $statusItem.ForeColor = $gray
        $notify.Text = 'Shrimp Agent - acik'
    }
}

$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 5000
$poll.Add_Tick({ Update-Status })
Update-Status
$poll.Start()

# Aç: uygulama açılınca kısa bilgi balonu
$notify.ShowBalloonTip(2500, 'Shrimp Agent', 'Tepside calisiyor. Sag tik -> yeni eslestirme kodu.', [System.Windows.Forms.ToolTipIcon]::Info)

$ctx = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($ctx)
$mutex.ReleaseMutex()
