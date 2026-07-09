import SwiftUI

struct TerminalTab: Identifiable {
    let id: String
    var title: String
    let backend: TerminalBackend
}

@MainActor
final class AppState: ObservableObject {
    // Bağlantı ayarları (kalıcı)
    @Published var host: String { didSet { UserDefaults.standard.set(host, forKey: "agentHost") } }
    @Published var portText: String { didSet { UserDefaults.standard.set(portText, forKey: "agentPort") } }
    @Published var token: String { didSet { UserDefaults.standard.set(token, forKey: "agentToken") } }

    // Durum
    @Published var connected = false
    @Published var lastError: String?
    @Published var projects: [ProjectInfo] = []
    @Published var sessionsByProject: [String: [SessionInfo]] = [:]
    @Published var expandedProjects: Set<String> = []
    @Published var terminals: [TerminalTab] = []
    @Published var remoteActive: [TerminalInfo] = []
    @Published var savedTerminals: [TerminalInfo] = []
    @Published var stats: StatsSnapshot?
    @Published var selection: SidebarSelection? = .terminals
    @Published var selectedTerminalID: String? { didSet { persistUIState() } }
    @Published var pcInfo: PCInfo?
    @Published var usage: Usage?
    @Published var desktopSessions: [DesktopSession] = []      // düz liste (Claude Desktop gibi)
    // Pin Shrimp'e ait (Desktop'ın pin deposu güvenilir okunamıyor). Kullanıcı sağ-tıkla yönetir.
    @Published var pinnedIDs: Set<String> = [] { didSet { UserDefaults.standard.set(Array(pinnedIDs), forKey: "pinnedIDs") } }
    private var refreshTimer: Timer?
    @Published var lastMac: String? { didSet { if let m = lastMac { UserDefaults.standard.set(m, forKey: "lastMac") } } }
    @Published var lastLanIP: String? { didSet { if let i = lastLanIP { UserDefaults.standard.set(i, forKey: "lastLanIP") } } }
    @Published var powerBusy = false
    @Published var powerNote: String?
    // Uyandırma (WOL) kartı akışı
    @Published var wakeState: WakeState = .idle
    @Published var wakeAttempts = 0
    @Published var wakeTopic: String { didSet { UserDefaults.standard.set(wakeTopic, forKey: "wakeTopic") } }
    private var wakeTask: Task<Void, Never>?
    // Kurulum sihirbazı
    @Published var setupComplete: Bool = false { didSet { UserDefaults.standard.set(setupComplete, forKey: "setupComplete") } }
    @Published var showSetupWizard = false
    @Published var pairingError: String?
    @Published var hasClaudeToken = false
    @Published var authRunning = false
    // Gömülü userspace Tailscale (tsnet) — resmi Tailscale yoksa devreye girer
    @Published var tsnetLocalPort: Int?
    @Published var tsnetAuthURL: String?
    @Published var tsnetRunning = false
    private var tsnetProc: Process?
    var tsnetActive: Bool { tsnetRunning && tsnetLocalPort != nil }
    /// Gerçek bağlantı hedefi: tsnet aktifse yerel forward, değilse doğrudan tailnet IP.
    var effectiveHost: String { tsnetActive ? "127.0.0.1" : host }
    var effectivePort: Int { tsnetActive ? (tsnetLocalPort ?? (Int(portText) ?? 8787)) : (Int(portText) ?? 8787) }
    @Published var events: [AppEvent] = []          // toast/bildirim akışı
    // Yeni Claude oturumu seçenekleri (Claude Desktop tarzı)
    @Published var selectedModel: String { didSet { UserDefaults.standard.set(selectedModel, forKey: "opt.model") } }
    @Published var permissionMode: String { didSet { UserDefaults.standard.set(permissionMode, forKey: "opt.mode") } }
    @Published var effort: String { didSet { UserDefaults.standard.set(effort, forKey: "opt.effort") } }

    private let statsSocket = StatsSocket()
    private var didRestoreTerminals = false
    private var connecting = false
    private var reconnectTimer: Timer?

    var api: AgentAPI {
        AgentAPI(host: effectiveHost, port: effectivePort, token: token)
    }

    init() {
        let d = UserDefaults.standard
        host = d.string(forKey: "agentHost") ?? ""
        portText = d.string(forKey: "agentPort") ?? "8787"
        token = d.string(forKey: "agentToken") ?? ""
        lastMac = d.string(forKey: "lastMac")
        lastLanIP = d.string(forKey: "lastLanIP")
        selectedModel = d.string(forKey: "opt.model") ?? ""      // "" = varsayılan
        permissionMode = d.string(forKey: "opt.mode") ?? "default"
        effort = d.string(forKey: "opt.effort") ?? ""            // "" = varsayılan
        pinnedIDs = Set(d.stringArray(forKey: "pinnedIDs") ?? [])
        // ntfy uyandırma konusu — ilk açılışta rastgele üret (ESP32'ye aynısı yazılır)
        if let t = d.string(forKey: "wakeTopic"), !t.isEmpty {
            wakeTopic = t
        } else {
            let rnd = (0..<20).map { _ in "0123456789abcdef".randomElement()! }
            wakeTopic = "shrimp-wol-" + String(rnd)
            d.set(wakeTopic, forKey: "wakeTopic")
        }
        // Zaten yapılandırılmışsa (host+token var) sihirbazı atla
        let cfgHost = d.string(forKey: "agentHost") ?? ""
        let cfgTok = d.string(forKey: "agentToken") ?? ""
        setupComplete = d.bool(forKey: "setupComplete") || (!cfgHost.isEmpty && !cfgTok.isEmpty)
    }

    /// Eşleştirme kodu: 6 haneli kısa kod (ntfy rendezvous) ya da base64 blob (geriye uyum).
    func applyPairingCode(_ code: String) {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if t.count == 6, t.allSatisfy(\.isNumber) {
            pairingError = nil
            Task { await fetchPairingViaNtfy(t) }
            return
        }
        applyPairingPayload(base64: t)
    }

    /// PC'nin ntfy'e yayınladığı payload'u kısa kodla çek → bağlan.
    private func fetchPairingViaNtfy(_ code: String) async {
        guard let url = URL(string: "https://ntfy.sh/shrimp-pair-\(code)/json?poll=1") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            pairingError = "Bağlantı hatası — internet var mı?"; return
        }
        for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").reversed() {
            guard let d = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  (o["event"] as? String) == "message",
                  let msg = o["message"] as? String, applyPairingPayloadReturning(base64: msg) else { continue }
            return
        }
        pairingError = "Kod bulunamadı — PC'deki eşleştirme penceresi açık mı? (kodun süresi dolmuş olabilir)"
    }

    @discardableResult
    private func applyPairingPayloadReturning(base64 t: String) -> Bool {
        guard let data = Data(base64Encoded: t),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let h = (obj["host"] as? String), !h.isEmpty,
              let tok = (obj["token"] as? String), !tok.isEmpty else { return false }
        pairingError = nil
        host = h
        if let port = obj["port"] as? Int { portText = String(port) }
        token = tok
        connect()
        return true
    }

    private func applyPairingPayload(base64 t: String) {
        if !applyPairingPayloadReturning(base64: t) {
            pairingError = "Kod çözülemedi — 6 haneli kodu doğru girdiğinden emin ol."
        }
    }

    /// Native chat için Anthropic yetkilendirme (agent setup-token'ı çalıştırır).
    func runSetupToken() {
        guard connected else { emit(.warning, "Önce bağlan", "Yetkilendirme için PC bağlantısı gerekli"); return }
        authRunning = true
        Task {
            let r = try? await api.post("/api/setup-token", body: [String: String](), as: SetupTokenResp.self)
            authRunning = false
            if r?.ok == true { hasClaudeToken = true; emit(.success, "Yetkilendirildi", "Claude native sohbet hazır") }
            else { emit(.error, "Yetkilendirme başarısız", r?.error ?? "PC'de tarayıcı onayı gerekebilir", code: "AUTH_FAIL", notify: true) }
        }
    }

    func refreshHealthToken() {
        Task { if let h = try? await api.get("/api/health", as: HealthResponse.self) { hasClaudeToken = h.hasClaudeToken ?? false } }
    }

    func connectIfConfigured() {
        startReconnectLoop()
        if !host.isEmpty && !token.isEmpty { connect() }
    }

    /// Bağlantı yoksa 4 sn'de bir sessizce yeniden dener (PC uyanana kadar).
    private func startReconnectLoop() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.connected && !self.connecting && !self.host.isEmpty && !self.token.isEmpty {
                    self.connect()
                }
            }
        }
    }

    func connect() {
        if connecting { return }
        connecting = true
        Task {
            // Doğrudan erişilemiyorsa (resmi Tailscale yok) + host tailnet IP → gömülü tsnet başlat
            if !tsnetActive, tsnetProc == nil, host.hasPrefix("100.") {
                let direct = AgentAPI(host: host, port: Int(portText) ?? 8787, token: token)
                let reachable = (try? await direct.get("/api/health", as: HealthResponse.self)) != nil
                if !reachable { startTsnet() }
            }
            do {
                _ = try await api.get("/api/health", as: HealthResponse.self)      // effective (direct ya da tsnet)
                let p = try await api.get("/api/projects", as: ProjectsResponse.self) // token'ı da doğrular
                projects = p.projects
                setConnected(true)
                lastError = nil
                tsnetAuthURL = nil
                await refreshTerminals()
                await fetchPCInfo()
                fetchUsage()
                fetchDesktopSessions()
                startStats()
                startRefreshLoop()
                restoreOpenTerminals()
            } catch {
                setConnected(false, error: error.localizedDescription)
            }
            connecting = false
        }
    }

    /// Bağlantı durumu geçişlerinde bir kez bildirim gönderir (spam yok).
    private func setConnected(_ v: Bool, error: String? = nil) {
        let was = connected
        connected = v
        if let error { lastError = error }
        if v && !was {
            emit(.success, "PC'ye bağlandı", stats?.hostname ?? pcInfo?.hostname ?? host)
        } else if !v && was {
            emit(.error, "Bağlantı koptu", "PC ile bağlantı kesildi. Otomatik yeniden deneniyor…",
                 code: "NET_DISCONNECT", notify: true)
        }
    }

    /// Olay yayınla: toast + (istenirse) sistem bildirimi.
    func emit(_ kind: AppEvent.Kind, _ title: String, _ message: String, code: String? = nil, notify: Bool = false) {
        let ev = AppEvent(kind: kind, title: title, message: message, code: code, at: Date())
        events.append(ev)
        if events.count > 5 { events.removeFirst(events.count - 5) }
        // 5 sn sonra otomatik kaldır
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.events.removeAll { $0.id == ev.id }
        }
        if notify || kind == .error {
            Notifier.notify(title, message, code: code, sound: kind == .error)
        }
    }

    // Açık terminalleri + seçili görünümü kalıcı hatırla → sonraki açılışta geri yükle.
    func persistUIState() {
        UserDefaults.standard.set(terminals.map { $0.id }, forKey: "openTerminalIDs")
        if let sel = selectedTerminalID { UserDefaults.standard.set(sel, forKey: "selectedTerminalID") }
    }

    private func restoreOpenTerminals() {
        guard !didRestoreTerminals else { return }
        let savedIDs = UserDefaults.standard.stringArray(forKey: "openTerminalIDs") ?? []
        if savedIDs.isEmpty { didRestoreTerminals = true; return }   // geri yüklenecek bir şey yok
        // PC terminal listesi henüz gelmediyse (geçici /api/terminals hatası) latch'leme;
        // refresh döngüsü yeniden dener — böylece tek geçici hata restore'u kalıcı bozmaz.
        guard !remoteActive.isEmpty else { return }
        didRestoreTerminals = true
        // PC'de hâlâ yaşayan (aktif) terminallerden, önceden açık olanları yeniden bağla.
        var restored = 0
        for t in remoteActive where savedIDs.contains(t.id) && !terminals.contains(where: { $0.id == t.id }) {
            attachTerminal(id: t.id, title: t.title)
            restored += 1
        }
        // önceki seçili terminali geri seç
        if let sel = UserDefaults.standard.string(forKey: "selectedTerminalID"),
           terminals.contains(where: { $0.id == sel }) {
            selectedTerminalID = sel
        }
        if restored > 0 {
            emit(.info, "Oturumlar geri yüklendi", "\(restored) terminal kaldığı yerden açıldı")
        }
    }

    private func startStats() {
        statsSocket.onStats = { [weak self] snap in
            Task { @MainActor in self?.stats = snap }
        }
        statsSocket.onConnectionChange = { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if self.connected != ok { self.setConnected(ok) }
            }
        }
        if let u = api.wsURL("/ws/stats") { statsSocket.start(url: u) }
    }

    func loadSessions(_ projectDir: String) {
        Task {
            if let r = try? await api.get("/api/sessions", query: ["project": projectDir], as: SessionsResponse.self) {
                sessionsByProject[projectDir] = r.sessions
            }
        }
    }

    func refreshTerminals() async {
        guard let list = try? await api.get("/api/terminals", as: TerminalListResponse.self) else { return }
        remoteActive = list.active
        savedTerminals = list.saved
    }

    func fetchPCInfo() async {
        guard let info = try? await api.get("/api/pcinfo", as: PCInfo.self) else { return }
        pcInfo = info
        if let m = info.mac { lastMac = m }
        if let i = info.lanIP { lastLanIP = i }
    }

    func fetchUsage() {
        Task {
            if let u = try? await api.get("/api/usage", as: Usage.self) { usage = u }
        }
    }

    /// Sohbet listesi + kullanımı periyodik yeniler (Desktop pin/başlık değişiklikleri yansısın).
    private func startRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connected else { return }
                self.fetchDesktopSessions()
                self.fetchUsage()
                // İlk restore geçici hatayla boş kaldıysa tekrar dene
                if !self.didRestoreTerminals { await self.refreshTerminals(); self.restoreOpenTerminals() }
            }
        }
    }

    /// Claude Desktop tarzı düz oturum listesi (Recents + pinned) — CANLI Desktop yansıması.
    func fetchDesktopSessions() {
        Task {
            guard let r = try? await api.get("/api/desktop-sessions", as: DesktopSessionsResponse.self) else { return }
            desktopSessions = r.sessions   // pinned bayrağı Desktop'tan canlı gelir
        }
    }
    // Pin Shrimp'e ait (kullanıcı sağ-tıkla yönetir).
    func togglePin(_ id: String) {
        if pinnedIDs.contains(id) { pinnedIDs.remove(id) } else { pinnedIDs.insert(id) }
    }
    var pinnedSessions: [DesktopSession] { desktopSessions.filter { pinnedIDs.contains($0.id) } }
    var recentSessions: [DesktopSession] { desktopSessions.filter { !pinnedIDs.contains($0.id) } }

    /// Gömülü userspace Tailscale'i (bundled shrimp-tsnet) başlat; login gerekirse authURL yayınlar.
    func startTsnet() {
        guard tsnetProc == nil else { return }
        guard let bin = Bundle.main.url(forResource: "shrimp-tsnet", withExtension: nil) else {
            emit(.warning, "Tailscale yardımcısı yok", "Resmi Tailscale kurulu olmalı"); return
        }
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Shrimp/tsnet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = "\(host):\(Int(portText) ?? 8787)"
        let p = Process()
        p.executableURL = bin
        p.arguments = ["--target", target, "--dir", dir.path, "--hostname", "shrimp-mac"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()   // tsnet log gürültüsünü yut
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            for raw in s.split(separator: "\n") {
                guard let d = raw.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let state = o["state"] as? String else { continue }
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case "needsLogin":
                        if let u = o["authURL"] as? String { self.tsnetAuthURL = u; self.tsnetRunning = false }
                    case "running":
                        if let listen = o["listen"] as? String, let port = Int(listen.split(separator: ":").last ?? "") { self.tsnetLocalPort = port }
                        self.tsnetRunning = true; self.tsnetAuthURL = nil
                        self.connect()
                    default: break
                    }
                }
            }
        }
        do { try p.run(); tsnetProc = p; emit(.info, "Tailscale (gömülü) başlıyor", "tailnet'e katılınıyor…") }
        catch { emit(.error, "tsnet başlatılamadı", error.localizedDescription) }
    }

    func openTsnetLogin() { if let s = tsnetAuthURL, let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    /// Taze bir native sohbet başlat (her çağrıda yeni ChatTarget id → yeni oturum).
    func newNativeChat() { selection = .nativeChat(ChatTarget()) }

    /// Düz listedeki bir oturumu terminalde devam ettir (slug + id ile).
    func resumeDesktopSession(_ s: DesktopSession) {
        Task {
            do {
                var body: [String: Any] = ["resumeSession": s.id]
                if let slug = s.slug { body["project"] = slug }
                else if !s.cwd.isEmpty { body["cwd"] = s.cwd }
                let created = try await api.post("/api/terminals", body: body, as: CreatedTerminal.self)
                attachTerminal(id: created.id, title: created.title)
                await refreshTerminals()
            } catch { lastError = error.localizedDescription }
        }
    }
    /// Geçmişini görüntüle (slug varsa).
    func viewDesktopSession(_ s: DesktopSession) {
        if let slug = s.slug { selection = .chat(slug, s.id) }
        else { resumeDesktopSession(s) }
    }

    /// PC güç eylemi (restart / sleep / shutdown). WOL için wake() ayrı.
    func power(_ action: String) {
        Task {
            powerBusy = true
            powerNote = nil
            defer { powerBusy = false }
            do {
                // try? YERINE do/catch: iletim hatası (PC kapalı/Tailscale down) artık
                // "başarı" sanılmaz — throw yakalanıp hata olarak gösterilir.
                let r = try await api.post("/api/power", body: ["action": action], as: PowerResponse.self)
                if let err = r.error {
                    powerNote = "Hata: \(err)"
                    emit(.error, "Güç işlemi başarısız", err, code: "POWER_\(action.uppercased())", notify: true)
                    return
                }
                switch action {
                case "restart": powerNote = "PC yeniden başlatılıyor…"; emit(.warning, "Yeniden başlatılıyor", "PC 5 sn içinde yeniden başlayacak", notify: true)
                case "sleep": powerNote = "PC uykuya alınıyor…"; emit(.info, "Uyku", "PC uykuya alınıyor", notify: true)
                case "shutdown": powerNote = "PC kapatılıyor…"; emit(.warning, "Kapatılıyor", "PC 5 sn içinde kapanacak", notify: true)
                default: break
                }
            } catch {
                powerNote = "Hata: \(error.localizedDescription)"
                emit(.error, "Güç işlemi başarısız", error.localizedDescription, code: "POWER_\(action.uppercased())", notify: true)
            }
        }
    }

    /// Uygulama açılışında PC uykudaysa uyandırma kartını başlat (kısa bekleme sonrası).
    func autoWakeIfNeeded() {
        guard wakeState == .idle, !connected, !host.isEmpty, !token.isEmpty else { return }
        startWake()
    }

    /// Uyandırma kartını başlat: yerel WOL + ntfy(ESP32) → sağlık → bağlan.
    func startWake() {
        guard !host.isEmpty, !token.isEmpty else { return }
        wakeTask?.cancel()
        wakeAttempts = 0
        wakeState = .waking
        wakeTask = Task { await runWake() }
    }

    func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
        wakeState = .idle
    }

    /// WOL (yerel broadcast — kalıcı MAC öncelikli) + ntfy(ESP32 uzak) döngüsü,
    /// sağlık kontrolüyle PC ayağa kalkana kadar; sonra bağlanıp kartı kapat.
    private func runWake() async {
        let deadline = Date().addingTimeInterval(90)
        while !Task.isCancelled, Date() < deadline {
            wakeAttempts += 1
            // 1) Yerel WOL — kalıcı (burned-in) MAC öncelikli (spoof aktif MAC değil)
            if let mac = pcInfo?.mac ?? lastMac {
                WakeOnLan.sendAll(mac: mac, lanIP: lastLanIP ?? pcInfo?.lanIP)
            }
            // 2) ntfy → ESP32 (uzak): aracı yerelde WOL yollar
            await publishWakeSignal()

            // 3) PC uyandı mı? Birkaç kez sağlık kontrolü
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                if (try? await api.get("/api/health", as: HealthResponse.self)) != nil {
                    wakeState = .verifying
                    connect()
                    for _ in 0..<12 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if connected {
                            wakeState = .connected
                            try? await Task.sleep(nanoseconds: 1_300_000_000)
                            wakeState = .idle
                            return
                        }
                    }
                }
            }
        }
        if !connected { wakeState = .failed }
    }

    /// ntfy.sh gizli konusuna "wake" yolla — ESP32 (abone) yerelde WOL gönderir.
    private func publishWakeSignal() async {
        guard !wakeTopic.isEmpty, let url = URL(string: "https://ntfy.sh/\(wakeTopic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data("wake".utf8)
        req.timeoutInterval = 8
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Tek tık: verilen (ya da varsayılan) dizinde Claude terminali aç (seçili model/mod/efor ile).
    func quickStartClaude(project: ProjectInfo? = nil) {
        Task {
            do {
                var body: [String: Any] = ["mode": "claude"]
                if let project { body["project"] = project.dir }
                if !selectedModel.isEmpty { body["model"] = selectedModel }
                if permissionMode != "default" { body["permissionMode"] = permissionMode }
                if !effort.isEmpty { body["effort"] = effort }
                let created = try await api.post("/api/terminals", body: body, as: CreatedTerminal.self)
                attachTerminal(id: created.id, title: created.title)
                await refreshTerminals()
            } catch { lastError = error.localizedDescription }
        }
    }

    /// Seçili terminale ham metin gönder (PTY girişi).
    func sendToActiveTerminal(_ text: String) {
        guard let id = selectedTerminalID,
              let tab = terminals.first(where: { $0.id == id }) else {
            emit(.warning, "Terminal yok", "Önce bir Claude terminali aç")
            return
        }
        tab.backend.sendInput(Data(text.utf8))
    }

    /// Çalışan terminalde modeli değiştir (/model komutu enjekte).
    func applyModelToActive(_ model: String) {
        selectedModel = model
        guard selectedTerminalID != nil else { return }
        sendToActiveTerminal("/model \(model.isEmpty ? "default" : model)\r")
        emit(.info, "Model değişti", model.isEmpty ? "varsayılan" : model)
    }

    /// Mac'ten görsel seç → PC'ye yükle → yolunu ilgili yere ekle.
    /// `onPath` verilirse (native chat) yol oraya iletilir; yoksa seçili terminale yazılır.
    func pickAndUploadImage(onPath: ((String) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                // Boyutu OKUMADAN önce kontrol et (GB'lık dosya RAM'e yüklenip patlamasın)
                if let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, sz > 20_000_000 {
                    emit(.error, "Görsel çok büyük", "20 MB üstü", code: "UPLOAD_TOO_BIG"); return
                }
                let data = try Data(contentsOf: url)
                if data.count > 20_000_000 { emit(.error, "Görsel çok büyük", "20 MB üstü", code: "UPLOAD_TOO_BIG"); return }
                let body: [String: Any] = ["name": url.lastPathComponent, "dataBase64": data.base64EncodedString()]
                struct UploadResp: Codable { var path: String; var name: String }
                let r = try await api.post("/api/upload", body: body, as: UploadResp.self)
                if let onPath { onPath(r.path) } else { sendToActiveTerminal("\(r.path) ") }
                emit(.success, "Görsel eklendi", r.name)
            } catch {
                emit(.error, "Yükleme başarısız", error.localizedDescription, code: "UPLOAD_FAIL")
            }
        }
    }

    /// Eski bir sohbeti terminalde devam ettir (claude --resume <id>).
    func resumeChat(project: String, sessionID: String) {
        Task {
            do {
                let created = try await api.post("/api/terminals",
                                                 body: ["project": project, "resumeSession": sessionID],
                                                 as: CreatedTerminal.self)
                attachTerminal(id: created.id, title: created.title)
                await refreshTerminals()
            } catch { lastError = error.localizedDescription }
        }
    }

    func newTerminal(cwd: String?, mode: String, resumeSaved: String? = nil) {
        Task {
            do {
                var body: [String: Any] = ["mode": mode]
                if let cwd, !cwd.isEmpty { body["cwd"] = cwd }
                if let resumeSaved { body["resumeSaved"] = resumeSaved }
                let created = try await api.post("/api/terminals", body: body, as: CreatedTerminal.self)
                attachTerminal(id: created.id, title: created.title)
                await refreshTerminals()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func attachTerminal(id: String, title: String) {
        if terminals.contains(where: { $0.id == id }) {
            selectedTerminalID = id
            selection = .terminals
            return
        }
        let backend = TerminalBackend(id: id, title: title)
        if let u = api.wsURL("/ws/terminal", query: ["id": id]) {
            backend.connect(url: u)
        }
        terminals.append(TerminalTab(id: id, title: title, backend: backend))
        selectedTerminalID = id
        selection = .terminals
    }

    /// Sekmeyi kapatır; PC'deki süreç çalışmaya devam eder (watchdog gerekirse kaydeder).
    func detachTab(_ id: String) {
        if let tab = terminals.first(where: { $0.id == id }) { tab.backend.close() }
        terminals.removeAll { $0.id == id }
        if selectedTerminalID == id { selectedTerminalID = terminals.last?.id }
        persistUIState()
        Task { await refreshTerminals() }
    }

    /// Süreci PC'de tamamen sonlandırır (kaydetmeden).
    func killTerminal(_ id: String) {
        Task {
            _ = try? await api.post("/api/terminals/kill", body: ["id": id], as: OkResponse.self)
            detachTab(id)
            await refreshTerminals()
        }
    }

    /// Hepsini PC'de kaydet + durdur (manuel watchdog).
    func saveStopAll() {
        Task {
            _ = try? await api.post("/api/save-stop", as: SaveStopResponse.self)
            for t in terminals { t.backend.close() }
            terminals.removeAll()
            selectedTerminalID = nil
            await refreshTerminals()
        }
    }

    func deleteSaved(_ id: String) {
        Task {
            _ = try? await api.post("/api/terminals/kill", body: ["id": id], as: OkResponse.self)
            await refreshTerminals()
        }
    }

    /// Uygulama kapanırken: sadece bağlantıları kapat — PC'deki watchdog
    /// grace süresi sonunda her şeyi kaydedip durdurur.
    func disconnectAll() {
        statsSocket.stop()
        for t in terminals { t.backend.close() }
    }
}
