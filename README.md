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

## Kurulum (en kolay yol)

### 1) Mac (Shrimp)
1. [**Releases**](https://github.com/Tumelo00/shrimp/releases) → **Shrimp-Kurulum.dmg** indir.
2. DMG'ye **sağ tık → Aç** (imzasız olduğu için çift-tık macOS tarafından engellenir).
3. Açılan pencerede **Shrimp Kurulum**'u **Applications**'a sürükle → **sağ tık → Aç**.
   Shrimp'i indirir, kurar, başlatır ve kendini temizler.

### 2) PC (Windows Agent) — tek komut
PowerShell'i **Yönetici olarak** aç ve yapıştır:
```powershell
irm https://raw.githubusercontent.com/Tumelo00/shrimp/main/agent/install.ps1 | iex
```
Node.js + agent'ı kurar, boot'ta otomatik başlayan servisi kaydeder, başlatır ve bir
**eşleştirme kodu** yazar.

### 3) Eşleştir
Shrimp'in kurulum sihirbazında eşleştirme kodunu yapıştır → bağlanır. Bitti.

> **Gereksinimler (install.ps1 eksikse uyarır):** PC'de **Claude Code** (kurulu + kendi
> hesabınla giriş: `npm i -g @anthropic-ai/claude-code`) ve **Tailscale** (Mac+PC aynı hesap).

---
<details><summary>Kaynaktan derleme (geliştirici)</summary>

**PC:** `cd agent && powershell -ExecutionPolicy Bypass -File scripts\setup.ps1`
**Mac:** `cd MacApp/ClaudeRemote && bash build_app.sh && open ~/Applications/Shrimp.app`
</details>

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
