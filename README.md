# 🦐 Shrimp — Mac'ten uzak Claude Code

Mac'ten, Tailscale üzerinden Windows PC'nizdeki **Claude Code**'u kullanın.
Claude gerçekte PC'de çalışır; arayüz Mac'te native bir uygulamadır (**Shrimp**).

- **Sol panel:** PC durumu (CPU/RAM/disk + uzaktan güç), Claude kullanım %'si, projeleriniz ve sohbet geçmişiniz
- **Sağ panel:** tam terminal (Claude Code TUI) — tek tıkla açılır
- Uygulamayı kapatınca PC'deki oturumlar korunur; tekrar açınca kaldığınız yerden devam

| Parça | Nerede | Ad |
|---|---|---|
| [`agent/`](agent/) | Windows PC | **Shrimp Service** (Node.js ajanı) |
| [`MacApp/ClaudeRemote/`](MacApp/ClaudeRemote/) | Mac | **Shrimp** (SwiftUI uygulaması) |

## Gereksinimler (her kullanıcı kendi hesabıyla)
- **Tailscale** — Mac ve PC aynı hesapta (ücretsiz): https://tailscale.com
- **Claude Code** — PC'de kurulu ve giriş yapılmış (kendi Claude/Anthropic hesabınız):
  `npm i -g @anthropic-ai/claude-code` → `claude` (bir kez giriş)
- **Node.js** (PC) ve **Xcode/Swift** (Mac, derlemek için)

> Bu depo kimsenin kişisel verisini içermez. Token her kurulumda **sizin PC'nizde**
> üretilir (`~/.claude-remote/config.json`), repoya girmez.

## Kurulum

### 1) PC (Shrimp Service) — tek komut
```powershell
cd claude-remote\agent
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```
Script: gereksinimleri kontrol eder, `npm install` yapar, **token üretir**, boot'ta
otomatik başlayan servisi kurar ve sonunda **Mac'e gireceğiniz bilgileri yazar**
(Tailscale IP + Port + Token).

### 2) Mac (Shrimp)
```bash
cd claude-remote/MacApp/ClaudeRemote
bash build_app.sh            # Shrimp.app üretir (~/Applications/Shrimp.app)
open ~/Applications/Shrimp.app
```
Uygulamada PC'nin **Tailscale IP** + **Port (8787)** + **Token**'ını girin. Bir kez
girince otomatik bağlanır; bir daha sormaz.

## Özellikler
- 🖥️ **PC kartı:** CPU/RAM/disk canlı + **Uyandır (WOL) / Yeniden Başlat / Uyku**
- ✦ **Claude kullanım %'si** (5 saatlik pencere, Claude Desktop tarzı bar)
- 💬 **Sohbet geçmişi:** eski sohbetleri okuma + tek tıkla **devam ettirme** (`claude --resume`)
- ⚡ **Tek tık Claude başlat** (proje seçimli)
- 📁 **Dosya gezgini** (PC dosyaları, salt-okunur)
- 🔔 **Bildirimler:** bağlantı/güç olayları için sistem bildirimi + uygulama içi toast
- 🔄 **Oto-bağlan + oturum koruma:** kapatıp açınca terminaller kaldığı yerden

## Notlar
- **WOL** (Uyandır): PC ve Mac aynı yerel ağda olmalı, PC'nin BIOS/NIC'inde WOL açık olmalı.
- **Watchdog:** ajan boot + logon'da otomatik başlar (oturum açılmadan da çalışır),
  Mac kapanınca PC'deki oturumları kaydeder.
- Ayrıntılı mimari: [PLAN.md](PLAN.md).

## Lisans / gizlilik
Kişisel token, oturum transkriptleri ve yapılandırma **repoya dahil değildir**
(`.gitignore` ile korunur). Herkes kendi Claude hesabıyla, kendi PC'sinde kullanır.
