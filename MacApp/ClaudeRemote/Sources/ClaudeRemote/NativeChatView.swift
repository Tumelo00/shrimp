import SwiftUI

// MARK: - Model

enum ChatRole { case user, assistant, tool, system }

struct ChatItem: Identifiable {
    let id: String
    var role: ChatRole
    var text: String = ""
    var toolName: String?
    var toolInput: String?
    var toolResult: String?
    var imageData: Data?
}

// MARK: - Oturum (WebSocket sürücüsü)

/// `/ws/chat` üzerinden claude -p (stream-json) oturumu. Prompt gönderir,
/// gelen JSON event'lerini render'lanabilir ChatItem'lara çevirir.
/// (UI'den çağrılan metotlar ana thread'de; receive döngüsü main'e dispatch eder.)
final class ChatSession: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var running = false
    @Published var connectedOnce = false
    @Published var errorText: String?
    @Published private(set) var revision = 0   // her içerik değişiminde artar (oto-kaydırma tetikleyici)

    private let host: String
    private let port: Int
    private let token: String
    private let model: String
    private let mode: String
    private let effort: String
    private var cwd: String?
    private(set) var sessionId: String?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isOpen = false
    private var toolIndexByID: [String: Int] = [:]
    // Canlı akış (partial) durumu
    private var streamIdx: [Int: Int] = [:]   // içerik bloğu index'i -> items index'i
    private var toolJson: [Int: String] = [:] // araç girdisi biriken ham JSON
    private var streamedMsg = false            // bu mesaj partial'larla kuruldu mu

    init(host: String, port: Int, token: String, model: String, mode: String, effort: String, resume: String?, cwd: String?) {
        self.host = host; self.port = port; self.token = token
        self.model = model; self.mode = mode; self.effort = effort
        self.sessionId = resume
        self.cwd = cwd
    }

    /// Çalışma dizinini oturum açılmadan önce ayarla (yeni sohbette proje seçimi).
    func setWorkingDir(_ c: String?) { if !isOpen { cwd = c } }

    /// Eski oturum geçmişini önden yükle (resume'da kullanıcı bağlamı görsün).
    /// Kullanıcı yükleme bitmeden mesaj yollamışsa geçmişi BAŞA ekle (kaybolmasın).
    private var didPreload = false
    func preload(_ history: [ChatItem]) {
        guard !didPreload else { return }
        didPreload = true
        items = history + items
        revision &+= 1
    }

    private func makeURL() -> URL? {
        var c = URLComponents()
        c.scheme = "ws"; c.host = host; c.port = port; c.path = "/ws/chat"
        // Native'de etkileşimli izin ekranı YOK → araçların çalışması için 'plan' hariç bypass.
        let effMode = (mode == "plan") ? "plan" : "bypassPermissions"
        var q = [URLQueryItem(name: "token", value: token),
                 URLQueryItem(name: "permissionMode", value: effMode)]
        if !model.isEmpty { q.append(URLQueryItem(name: "model", value: model)) }
        if !effort.isEmpty { q.append(URLQueryItem(name: "effort", value: effort)) }
        if let r = sessionId { q.append(URLQueryItem(name: "resume", value: r)) }
        if let w = cwd, !w.isEmpty { q.append(URLQueryItem(name: "cwd", value: w)) }
        c.queryItems = q
        return c.url
    }

    private func open() {
        guard let url = makeURL() else { errorText = "URL kurulamadı"; return }
        session?.invalidateAndCancel()   // önceki oturumu sızdırma (reconnect'te)
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        let s = URLSession(configuration: cfg)
        session = s
        let t = s.webSocketTask(with: url)
        t.maximumMessageSize = 16 * 1024 * 1024
        task = t
        isOpen = true
        connectedOnce = true
        t.resume()
        receiveLoop()
    }

    /// Kullanıcı mesajı gönder (gerekirse bağlantıyı aç / resume ile yeniden bağlan).
    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(ChatItem(id: UUID().uuidString, role: .user, text: t))
        if !isOpen { open() }
        running = true
        errorText = nil
        let payload = ["type": "prompt", "text": t]
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            task?.send(.string(s)) { [weak self] err in
                guard let self, let err else { return }
                DispatchQueue.main.async {
                    self.running = false
                    self.errorText = "Gönderilemedi: \(err.localizedDescription)"
                }
            }
        }
    }

    /// Üretimi durdur (süreç kapanır; sessionId ile sonra devam edilebilir).
    func stop() {
        running = false
        isOpen = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        streamedMsg = false; streamIdx.removeAll(); toolJson.removeAll()   // yarım akış durumunu temizle
    }

    func close() { stop(); session?.invalidateAndCancel(); session = nil }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            // TÜM işleme + özyineleme ana thread'de → task/session/isOpen tek thread'den
            // erişilir (veri yarışı yok).
            DispatchQueue.main.async {
                switch result {
                case .failure:
                    if self.isOpen {   // kasıtlı stop()/close() değil, gerçek kopma
                        self.isOpen = false
                        self.running = false
                        self.errorText = "Bağlantı koptu — mesaj gönderilemedi olabilir."
                    }
                case .success(let msg):
                    if case .string(let s) = msg { self.handle(s) }
                    self.receiveLoop()
                }
            }
        }
    }

    // MARK: event işleme

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "system":
            if let sid = obj["session_id"] as? String { sessionId = sid }
        case "stream_event":
            if let ev = obj["event"] as? [String: Any] { handleStream(ev) }
        case "assistant":
            // partial'larla kurulduysa metin/araç bloklarını tekrar EKLEME (görsel hariç)
            if let m = obj["message"] as? [String: Any],
               let content = m["content"] as? [[String: Any]] {
                for block in content {
                    let bt = block["type"] as? String
                    if bt == "image" { appendAssistantBlock(block) }
                    else if !streamedMsg { appendAssistantBlock(block) }
                }
            }
        case "user":
            if let m = obj["message"] as? [String: Any],
               let content = m["content"] as? [[String: Any]] {
                for block in content { appendUserBlock(block) }
            }
        case "result":
            running = false
            streamedMsg = false; streamIdx.removeAll(); toolJson.removeAll()
            if let sid = obj["session_id"] as? String { sessionId = sid }
            if let isErr = obj["is_error"] as? Bool, isErr,
               let r = obj["result"] as? String { errorText = r }
        case "shrimp_error":
            // Yalnızca gerçek spawn hatası. (stderr = hook/uyarı gürültüsü → yok say.)
            if let t = obj["text"] as? String, !t.isEmpty {
                let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { errorText = String(clean.prefix(300)) }
            }
        case "shrimp_exit":
            running = false; isOpen = false
        default:
            break
        }
        revision &+= 1   // her event sonrası oto-kaydırma tetiklensin
    }

    /// Anthropic SSE partial event'leri → items'a canlı yaz (token-token akış).
    private func handleStream(_ ev: [String: Any]) {
        guard let et = ev["type"] as? String else { return }
        switch et {
        case "message_start":
            streamedMsg = false; streamIdx.removeAll(); toolJson.removeAll()
        case "content_block_start":
            guard let idx = ev["index"] as? Int,
                  let cb = ev["content_block"] as? [String: Any],
                  let cbt = cb["type"] as? String else { return }
            streamedMsg = true
            if cbt == "text" {
                // Metin öğesini ilk token'da oluştur (boş balon flaşı olmasın)
            } else if cbt == "tool_use" {
                let name = (cb["name"] as? String) ?? "araç"
                let id = (cb["id"] as? String) ?? UUID().uuidString
                items.append(ChatItem(id: id, role: .tool, toolName: name, toolInput: nil))
                streamIdx[idx] = items.count - 1
                toolIndexByID[id] = items.count - 1
                toolJson[idx] = ""
            }
        case "content_block_delta":
            guard let idx = ev["index"] as? Int,
                  let delta = ev["delta"] as? [String: Any],
                  let dt = delta["type"] as? String else { return }
            if dt == "text_delta", let tx = delta["text"] as? String {
                // İlk token'da metin öğesini oluştur
                var j = streamIdx[idx]
                if j == nil {
                    items.append(ChatItem(id: UUID().uuidString, role: .assistant, text: ""))
                    j = items.count - 1
                    streamIdx[idx] = j
                }
                if let jj = j, jj < items.count { items[jj].text += tx }
            } else if dt == "input_json_delta", let pj = delta["partial_json"] as? String,
                      let ii = streamIdx[idx], ii < items.count {
                toolJson[idx, default: ""] += pj
                items[ii].toolInput = toolJson[idx]
            }
        case "content_block_stop":
            guard let idx = ev["index"] as? Int, let ii = streamIdx[idx], ii < items.count,
                  let raw = toolJson[idx], !raw.isEmpty,
                  let d = raw.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d),
                  let pretty = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted]),
                  let s = String(data: pretty, encoding: .utf8) else { return }
            items[ii].toolInput = s
        default:
            break
        }
    }

    private func appendAssistantBlock(_ block: [String: Any]) {
        guard let t = block["type"] as? String else { return }
        switch t {
        case "text":
            if let txt = block["text"] as? String, !txt.isEmpty {
                items.append(ChatItem(id: UUID().uuidString, role: .assistant, text: txt))
            }
        case "tool_use":
            let name = (block["name"] as? String) ?? "araç"
            let id = (block["id"] as? String) ?? UUID().uuidString
            var inputStr: String?
            if let input = block["input"], let d = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted]) {
                inputStr = String(data: d, encoding: .utf8)
            }
            items.append(ChatItem(id: id, role: .tool, toolName: name, toolInput: inputStr))
            toolIndexByID[id] = items.count - 1
        case "image":
            if let img = decodeImage(block) {
                items.append(ChatItem(id: UUID().uuidString, role: .assistant, imageData: img))
            }
        default:
            break
        }
    }

    private func appendUserBlock(_ block: [String: Any]) {
        guard let t = block["type"] as? String, t == "tool_result" else { return }
        let useId = (block["tool_use_id"] as? String) ?? ""
        let resText = toolResultText(block["content"])
        if let idx = toolIndexByID[useId], idx < items.count {
            items[idx].toolResult = resText
        }
    }

    private func toolResultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private func decodeImage(_ block: [String: Any]) -> Data? {
        guard let src = block["source"] as? [String: Any],
              let b64 = src["data"] as? String else { return nil }
        return Data(base64Encoded: b64)
    }
}

// MARK: - Görünüm

struct NativeChatView: View {
    @EnvironmentObject var app: AppState
    let target: ChatTarget

    @StateObject private var chat: ChatSession
    @State private var input = ""
    @State private var atBottom = true
    @State private var showJump = false
    @State private var viewportH: CGFloat = 0
    @State private var loadingHistory = false
    @State private var projectName: String?   // yeni sohbette seçili çalışma dizini adı

    init(app: AppState, target: ChatTarget) {
        self.target = target
        _chat = StateObject(wrappedValue: ChatSession(
            host: app.effectiveHost, port: app.effectivePort, token: app.token,
            model: app.selectedModel, mode: app.permissionMode, effort: app.effort,
            resume: target.resume, cwd: target.cwd))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            if let err = chat.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
            }
            inputBar
        }
        .navigationTitle(target.title ?? "Yeni Sohbet")
        .task(id: target.resume ?? "new") { await loadHistory() }
        .onChange(of: chat.running) { running in
            // Tur bitince yeni oturum "Sohbetler" listesine düşsün → hemen yenile
            if !running { app.fetchDesktopSessions() }
        }
        .onDisappear { chat.close() }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.items.isEmpty {
                            VStack(spacing: 10) {
                                if loadingHistory { ProgressView().controlSize(.small) }
                                Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.secondary)
                                Text("Claude ile sohbet").foregroundStyle(.secondary)
                                Text(target.resume != nil ? "Bu oturum kaldığı yerden devam eder." : "Bir mesaj yazarak başla.")
                                    .font(.caption).foregroundStyle(.tertiary)
                                // Yeni sohbet: proje bağlamı seç (yoksa ev dizini — bağlamsız)
                                if target.resume == nil {
                                    Menu {
                                        Button("Ev dizini (bağlamsız)") { chat.setWorkingDir(nil); projectName = nil }
                                        Divider()
                                        ForEach(app.projects) { p in
                                            Button(p.name) { chat.setWorkingDir(p.path); projectName = p.name }
                                        }
                                    } label: {
                                        Label(projectName ?? "Proje seç (Claude bu dizinde çalışır)", systemImage: "folder")
                                            .font(.caption)
                                    }
                                    .menuStyle(.button).fixedSize().padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.top, 50)
                        }
                        ForEach(chat.items) { item in
                            ChatItemView(item: item)
                        }
                        if chat.running {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Claude yazıyor…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .background(GeometryReader { g in
                                Color.clear.preference(key: BottomOffsetKey.self,
                                    value: g.frame(in: .named("nchat")).maxY)
                            })
                    }
                    .padding()
                }
                .coordinateSpace(name: "nchat")
                .onAppear { viewportH = outer.size.height }
                .onChange(of: outer.size.height) { viewportH = $0 }
                .onPreferenceChange(BottomOffsetKey.self) { maxY in
                    let now = (maxY - viewportH) < 48
                    if now != atBottom { atBottom = now }
                    if now && showJump { showJump = false }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showJump {
                    Button {
                        withAnimation(.easeOut(duration: 0.28)) { proxy.scrollTo("bottom", anchor: .bottom) }
                        showJump = false
                    } label: {
                        Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white).frame(width: 34, height: 34)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain).padding(16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showJump)
            .onChange(of: chat.revision) { _ in
                // İçerik büyüdükçe (token akışı dahil) dibe pinliyse takip et; değilse ok göster
                if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
                else { showJump = true }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Bir mesaj yaz…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit(sendCurrent)
                if chat.running {
                    Button(action: { chat.stop() }) {
                        Image(systemName: "stop.circle.fill").font(.system(size: 26)).foregroundStyle(.red)
                    }.buttonStyle(.plain).help("Durdur")
                } else {
                    Button(action: sendCurrent) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                            .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    }
                    .buttonStyle(.plain).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Gönder")
                }
            }
            // Model · İzin · Efor satırı (Claude Desktop tarzı)
            HStack(spacing: 8) {
                Menu {
                    ForEach(ClaudeOptions.modes, id: \.1) { m in
                        Button { app.permissionMode = m.1 } label: {
                            HStack { Image(systemName: m.2); Text(m.0); if app.permissionMode == m.1 { Spacer(); Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: ClaudeOptions.modeIcon(app.permissionMode)).font(.system(size: 10))
                        Text(ClaudeOptions.modeShort(app.permissionMode)).font(.caption).fontWeight(.medium)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(app.permissionMode == "bypassPermissions" ? Color.yellow.opacity(0.22) : Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(app.permissionMode == "bypassPermissions" ? Color.yellow : Color.primary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

                Button {
                    // Görseli PC'ye yükle → yolunu SOHBET girdisine ekle (terminale değil).
                    app.pickAndUploadImage { path in
                        input = input.isEmpty ? path : input + " " + path
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24).background(Color.secondary.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help("Görsel/dosya ekle (sohbete)")

                Spacer()
                Menu {
                    ForEach(ClaudeOptions.models, id: \.1) { m in
                        Button { app.selectedModel = m.1 } label: {
                            HStack { Text(m.0); if app.selectedModel == m.1 { Spacer(); Image(systemName: "checkmark") } }
                        }
                    }
                } label: { Text(ClaudeOptions.modelLabel(app.selectedModel)).font(.caption).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

                Menu {
                    ForEach(ClaudeOptions.efforts, id: \.self) { e in
                        Button { app.effort = e } label: {
                            HStack { Text(ClaudeOptions.effortShort(e)); if app.effort == e { Spacer(); Image(systemName: "checkmark") } }
                        }
                    }
                } label: { Text(ClaudeOptions.effortShort(app.effort)).font(.caption).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if chat.connectedOnce {
                Text("Model/izin/efor değişiklikleri yeni sohbette geçerlidir")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func sendCurrent() {
        let t = input
        input = ""
        chat.send(t)
    }

    /// Eski oturum ise geçmişi (son ~60 mesaj) yükleyip göster.
    private func loadHistory() async {
        guard let rid = target.resume, let slug = target.slug else { return }
        loadingHistory = true
        defer { loadingHistory = false }
        if let page = try? await app.api.get("/api/chat",
                                             query: ["project": slug, "id": rid, "limit": "60"],
                                             as: ChatPage.self) {
            let hist = page.messages.map {
                ChatItem(id: UUID().uuidString,
                         role: $0.role == "user" ? ChatRole.user : ChatRole.assistant,
                         text: $0.text)
            }
            chat.preload(hist)
        }
    }
}

// MARK: - Öğe render

struct ChatItemView: View {
    let item: ChatItem

    var body: some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sen").font(.caption2).foregroundStyle(.secondary)
                    Text(item.text).textSelection(.enabled)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        case .assistant:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude").font(.caption2).foregroundStyle(.secondary)
                    if let img = item.imageData, let ns = NSImage(data: img) {
                        Image(nsImage: ns).resizable().scaledToFit().frame(maxWidth: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RichText(item.text)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 50)
            }
        case .tool:
            ChatToolView(item: item)
        case .system:
            Text(item.text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Araç kullanımı — açılır-kapanır (girdi + sonuç).
struct ChatToolView: View {
    let item: ChatItem
    @State private var expanded = false

    private var hasBody: Bool { (item.toolInput?.isEmpty == false) || (item.toolResult?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasBody { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
            } label: {
                HStack(spacing: 6) {
                    if hasBody {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 10)
                    } else { Spacer().frame(width: 10) }
                    Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(Color.accentColor)
                    Text(item.toolName ?? "araç").font(.system(.caption, design: .monospaced)).foregroundStyle(.primary)
                    if item.toolResult == nil { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let inp = item.toolInput, !inp.isEmpty {
                        CodeBlock(text: inp)
                    }
                    if let res = item.toolResult, !res.isEmpty {
                        Text("sonuç").font(.system(size: 9)).foregroundStyle(.tertiary)
                        CodeBlock(text: String(res.prefix(4000)))
                    }
                }
                .padding(.leading, 16).padding(.top, 4)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Zengin metin (markdown + kod blokları)

/// ``` çitleriyle bölüp: kod bloklarını monospace kutuda, gerisini markdown olarak.
struct RichText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                if seg.isCode { CodeBlock(text: seg.text) }
                else { Text(markdown(seg.text)).textSelection(.enabled) }
            }
        }
    }

    private struct Seg { let text: String; let isCode: Bool }
    private func segments() -> [Seg] {
        var out: [Seg] = []
        let parts = raw.components(separatedBy: "```")
        // Tek sayıda ``` (kapanmamış fence) → son bölge KOD DEĞİL, düz metin
        // (streaming sırasında gelen tek ``` prose'u kod kutusuna sokmasın).
        let hasUnclosed = (parts.count - 1) % 2 == 1
        for (i, p) in parts.enumerated() {
            let isLast = i == parts.count - 1
            let isCode = (i % 2 == 1) && !(hasUnclosed && isLast)
            var t = p
            if isCode {
                // ilk satır dil etiketi olabilir → at
                if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            }
            // boş bölgeleri atla (kod dahil → boş siyah kutu olmasın)
            if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            out.append(Seg(text: t, isCode: isCode))
        }
        return out.isEmpty ? [Seg(text: raw, isCode: false)] : out
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct CodeBlock: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
        }
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }
}
