# ClaudeRemote (Mac tarafı)

SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) ile yazılmış
native macOS istemcisi. Windows PC'deki `claude-remote-agent`'a Tailscale
üzerinden bağlanır.

## Derleme ve paketleme

Gereksinim: macOS 13+, Xcode (veya Command Line Tools). Apple Silicon + macOS 26'da
test edildi (Swift 6.3, Xcode 26).

**Önerilen — tek script** (derler, `.app` paketler, ad-hoc imzalar):
```bash
cd MacApp/ClaudeRemote
bash build_app.sh          # release; debug icin: bash build_app.sh debug
open ~/Applications/ClaudeRemote.app
```

**Xcode ile:** `MacApp/ClaudeRemote` klasörünü aç (Package.swift'i seç), scheme
`ClaudeRemote`, Run.

> **KRİTİK — ATS ayarı:** Uygulama Tailscale üzerinden TLS'siz `http://`/`ws://`
> konuşur. Bunun için `NSAppTransportSecurity` altında **yalnızca**
> `NSAllowsArbitraryLoads=true` olmalı. **`NSAllowsLocalNetworking` EKLENMEZ** —
> macOS 26'da onun varlığı `NSAllowsArbitraryLoads`'u yok saydırıyor ve Tailscale
> adresi "yerel ağ" sayılmadığı için tüm cleartext istekler ATS ile engelleniyor
> (sessiz bağlanamama). `build_app.sh`'in ürettiği Info.plist bu kurala uygun.
>
> Not: SwiftTerm sürümüyle delegate imzaları uyuşmazsa `TerminalHostView.swift`
> içindeki Coordinator metodlarını Xcode'un önerdiği imzalarla eşleştir.

## İlk bağlantı

1. PC'de agent çalışıyor olmalı (`npm start` — README'sine bak).
2. PC'de Tailscale açık olmalı; IP: `tailscale ip -4` (örn. `100.x.y.z`).
3. Uygulamayı aç → IP + port (8787) + token gir → Bağlan.
   Token PC'de `%USERPROFILE%\.claude-remote\config.json` içinde.

## Özellikler

- **Sol sidebar:** projeler → sohbet oturumları (Claude Desktop tarzı),
  PC'de çalışan/kayıtlı terminaller, dosya gezgini
- **Terminal:** tam xterm emülasyonu (SwiftTerm), sekmeli; Claude Code
  gerçekte PC'de çalışır
- **Üst çubuk:** PC'nin CPU / RAM / disk / uptime bilgisi (2 sn'de bir push)
- **Kapanış:** uygulama kapanınca PC'deki watchdog 60 sn sonra tüm
  terminalleri kaydedip durdurur; "Devam" ile kaldığın yerden açarsın
- **Kaydet & Durdur** butonu: aynısını beklemeden hemen yapar
