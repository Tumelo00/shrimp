# Claude Remote — Mac'ten Windows'taki Claude Code'a Uzak Arayüz

## Amaç
Mac'te çalışan native SwiftUI uygulaması, Tailscale üzerinden Windows PC'deki
Claude Code'u kullanır. Terminal PC'de çalışır, arayüz Mac'tedir.

## Mimari

```
┌─ Mac (SwiftUI) ─────────────────┐          ┌─ Windows PC (Node.js Agent) ────────┐
│ Sidebar: Projeler + Chatler     │ Tailscale│ HTTP+WS sunucu (port 8787)          │
│ Terminal: SwiftTerm (xterm)     │ ◄──────► │ ConPTY: cmd /c claude               │
│ StatsBar: CPU/RAM/Disk          │ WS+REST  │ ~/.claude/projects JSONL okuyucu    │
│ Dosya gezgini                   │  +token  │ Watchdog: kopunca kaydet + durdur   │
└─────────────────────────────────┘          └─────────────────────────────────────┘
```

## Protokol
- Kimlik: `Authorization: Bearer <token>` veya `?token=` (WS için). Token ilk
  çalıştırmada üretilir: `%USERPROFILE%\.claude-remote\config.json`
- REST:
  - `GET /api/health` (auth'suz sağlık)
  - `GET /api/projects` — proje listesi (~/.claude/projects)
  - `GET /api/sessions?project=<dir>` — oturum listesi (özet + tarih)
  - `GET /api/chat?project=&id=&limit=&before=` — mesajlar (sayfalı, sondan)
  - `GET /api/files?path=` / `GET /api/file?path=` — dosya gezgini (salt-okunur)
  - `GET /api/terminals` — aktif + kayıtlı terminaller
  - `POST /api/terminals` `{cwd, mode: claude|shell, args?, resumeSaved?}` → `{id}`
  - `POST /api/terminals/kill` `{id}`
  - `POST /api/save-stop` — hepsini kaydet ve durdur (manuel)
  - `GET /api/stats` — anlık istatistik
- WS:
  - `/ws/terminal?id=` — binary çerçeve = PTY G/Ç; text JSON = kontrol
    (`{type:resize,cols,rows}`, sunucudan `{type:exit,code}`, `{type:title}`)
  - `/ws/stats` — 2sn'de bir push (abone varken)

## Optimizasyonlar (kalite bozulmadan)
1. **Çıktı coalescing**: PTY çıktısı 16ms pencerede birleştirilip tek binary
   frame olarak gider → binlerce küçük paket yerine az sayıda büyük paket.
2. **Backpressure**: istemcinin WS tamponu 1MB'ı aşarsa PTY `pause()`,
   256KB altına inince `resume()` → veri kaybı yok, RAM patlaması yok.
3. **İzleyici yoksa yayın yok**: terminal çıktısı sadece scrollback ring
   buffer'ına (512KB/oturum) yazılır; istatistik zamanlayıcısı abone yokken durur.
4. **JSONL tembel okuma**: oturum listesi için dosyanın ilk 64KB'ı taranır;
   tam sohbet mtime anahtarıyla önbelleklenir (LRU, 8 giriş).
5. **Disk bilgisi 30sn önbellek** (CIM sorgusu pahalı), CPU% os.cpus() deltası
   (ek süreç yok). Bağımlılık sadece `ws` + `@lydell/node-pty` (prebuilt).
6. **Mac tarafı**: stats WS push (polling yok), chat sayfalı yükleme
   (son 60 mesaj), terminal girdisi binary (JSON sarmalama yok).

## Watchdog davranışı
- Son WS istemcisi kopunca `graceMs` (60sn) sayaç başlar (yeniden bağlanmada iptal).
- Süre dolunca: her aktif terminalin scrollback + meta'sı
  `%USERPROFILE%\.claude-remote\state\sessions\<id>\` altına yazılır, PTY kapatılır.
  Claude Code kendi transcript'ini zaten sürekli kaydettiği için kayıp olmaz;
  `resumeSaved` ile açılan terminal `claude --continue` + eski scrollback ile döner.
- 30sn'de bir WS ping; cevapsız (uyuyan Mac) bağlantılar koparılır → watchdog
  zombi bağlantı yüzünden takılı kalmaz.
- Agent SIGINT alırsa da kaydedip çıkar.

## Faz 2 (sonra)
- ESP32 WOL: Mac app'e "PC'yi Uyandır" (ESP32 HTTP endpoint'ine istek) ve
  "PC'yi Kapat" (`POST /api/shutdown` → `shutdown /s /t 30`, önce save-stop).
- Kullanıcı bunu ayrıca planlayacak; agent tarafına endpoint eklemek 10 dk'lık iş.

## Dizinler
- `agent/` — Windows PC agent (Node.js)
- `MacApp/ClaudeRemote/` — SwiftUI uygulaması (Swift Package; `swift run` veya Xcode)
