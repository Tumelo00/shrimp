# claude-remote-agent (Windows PC tarafı)

Mac'teki ClaudeRemote uygulamasının bağlandığı hafif Node.js agent'ı.
Bağımlılık: sadece `ws` + `@lydell/node-pty` (prebuilt, derleyici gerektirmez).

## Kurulum ve çalıştırma

```powershell
cd C:\kumas_final\claude-remote\agent
npm install
npm start
```

İlk çalıştırmada `%USERPROFILE%\.claude-remote\config.json` oluşur ve **token**
konsola yazılır — Mac uygulamasına bu token'ı gireceksin.

Varsayılan olarak **Tailscale IP'sine** bind olur (Tailscale kapalıysa 127.0.0.1).
Tailscale'i başlatmayı unutma: sistem tepsisinden veya `tailscale up`.

## Otomatik başlatma (oturum açılışında, gizli)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-task.ps1
Start-ScheduledTask -TaskName ClaudeRemoteAgent
```

## Watchdog davranışı

- Mac uygulaması kapanınca/bağlantı kopunca 60 sn beklenir (config: `graceMs`).
- Süre dolunca tüm terminallerin scrollback'i + çalışma dizini
  `%USERPROFILE%\.claude-remote\state\sessions\` altına kaydedilir ve süreçler durdurulur.
- Claude Code kendi transcript'ini zaten sürekli kaydettiği için sohbet kaybolmaz;
  Mac'ten "Devam" dediğinde `claude --continue` + eski ekran görüntüsüyle açılır.
- Boştayken agent CPU kullanmaz: izleyici yokken terminal yayını ve istatistik
  zamanlayıcısı tamamen durur.

## Test

```powershell
node scripts\smoke.js   # 13 uçtan uca test (REST + WS + PTY + save/resume)
```

## config.json alanları

| Alan | Varsayılan | Açıklama |
|---|---|---|
| `port` | 8787 | Dinlenen port |
| `host` | `auto` | `auto` = Tailscale IP; sabit IP de yazılabilir |
| `token` | (üretilir) | Mac uygulamasının kimlik anahtarı |
| `graceMs` | 60000 | Kopuş sonrası kaydet+durdur beklemesi |
| `scrollbackBytes` | 524288 | Oturum başına ekran geçmişi tamponu |
| `statsIntervalMs` | 2000 | İstatistik push aralığı |
| `fileRoots` | `["C:\\"]` | Dosya gezgininin erişebildiği kökler |
