import SwiftUI

/// Dip çapasının kaydırma görünümü içindeki dikey konumu — oto-kaydırma kararı için.
struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Bir Claude Code oturumunun sohbet geçmişi (salt-okunur, sayfalı).
struct ChatHistoryView: View {
    @EnvironmentObject var app: AppState
    let project: String
    let sessionID: String

    @State private var messages: [ChatMessage] = []
    @State private var total = 0
    @State private var start = 0
    @State private var loading = false
    @State private var error: String?

    // Akıllı oto-kaydırma durumu
    @State private var atBottom = true          // kullanıcı dibe sabit mi
    @State private var showJump = false          // "aşağı in" oku görünsün mü
    @State private var viewportH: CGFloat = 0
    @State private var prepending = false         // eski mesaj yükleniyor (ok tetiklenmesin)

    var body: some View {
        Group {
            if loading && messages.isEmpty {
                ProgressView("Yükleniyor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    GeometryReader { outer in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if start > 0 {
                                    HStack {
                                        Spacer()
                                        Button("↑ Önceki \(min(60, start)) mesajı yükle") { loadMore() }
                                            .buttonStyle(.link)
                                        Spacer()
                                    }
                                }
                                ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                                    MessageBubble(message: m)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                                    .background(GeometryReader { g in
                                        Color.clear.preference(key: BottomOffsetKey.self,
                                            value: g.frame(in: .named("chatScroll")).maxY)
                                    })
                            }
                            .padding()
                        }
                        .coordinateSpace(name: "chatScroll")
                        .onAppear { viewportH = outer.size.height }
                        .onChange(of: outer.size.height) { viewportH = $0 }
                        .onPreferenceChange(BottomOffsetKey.self) { maxY in
                            // dip çapası viewport'un altındaysa maxY büyük olur
                            let nowAtBottom = (maxY - viewportH) < 48
                            if nowAtBottom != atBottom { atBottom = nowAtBottom }
                            if nowAtBottom && showJump { showJump = false }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showJump {
                            Button {
                                withAnimation(.easeOut(duration: 0.28)) { proxy.scrollTo("bottom", anchor: .bottom) }
                                showJump = false
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.accentColor, in: Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16).padding(.bottom, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: showJump)
                    .onChange(of: messages.count) { _ in
                        if prepending {
                            prepending = false   // eski mesaj eklendi (yukarı) → ok gösterme
                        } else if atBottom {
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                        } else {
                            showJump = true   // kullanıcı yukarıda; geride kaldı → ok göster
                        }
                    }
                }
            }
        }
        .navigationTitle("Sohbet · \(String(sessionID.prefix(8)))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.resumeChat(project: project, sessionID: sessionID)
                } label: {
                    Label("Devam Et", systemImage: "play.fill")
                }
                .help("Bu sohbeti terminalde Claude ile devam ettir")
            }
        }
        .task(id: project + "/" + sessionID) {
            await load()
            // CANLI: yeni mesajları periyodik yokla, kapatmadan gelsin
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await pollNew()
            }
        }
    }

    /// Yeni mesaj geldiyse sona ekle (tüm listeyi yeniden yüklemeden).
    private func pollNew() async {
        guard let page = try? await app.api.get("/api/chat",
                                                query: ["project": project, "id": sessionID, "limit": "60"],
                                                as: ChatPage.self) else { return }
        guard page.total > total else { return }
        let newCount = min(page.total - total, page.messages.count)
        if newCount > 0 {
            messages.append(contentsOf: page.messages.suffix(newCount))
            total = page.total
        }
    }

    private func load() async {
        loading = true
        error = nil
        messages = []
        do {
            let page = try await app.api.get("/api/chat",
                                             query: ["project": project, "id": sessionID, "limit": "60"],
                                             as: ChatPage.self)
            messages = page.messages
            total = page.total
            start = page.start
        } catch let e {
            error = e.localizedDescription
        }
        loading = false
    }

    private func loadMore() {
        Task {
            if let page = try? await app.api.get("/api/chat",
                                                 query: ["project": project, "id": sessionID,
                                                         "limit": "60", "before": String(start)],
                                                 as: ChatPage.self) {
                prepending = true   // sonraki count-onChange ok tetiklemesin
                messages = page.messages + messages
                start = page.start
            }
        }
    }
}

// Araç bloğu (edit/write/bash/read…) — özet + açılır diff gövdesi.
struct ToolBlock {
    let symbol: String       // ✎ ＋ 👁 🔎 ☑ ⚙ $
    let title: String        // dosya yolu / komut
    let bodyLines: [String]  // + / - / … satırları
    var additions: Int { bodyLines.filter { $0.hasPrefix("+ ") }.count }
    var deletions: Int { bodyLines.filter { $0.hasPrefix("- ") }.count }
    var hasBody: Bool { !bodyLines.isEmpty }
}

enum MsgSegment { case prose(String); case tool(ToolBlock) }

private let toolPrefixChars: Set<Character> = ["✎", "＋", "👁", "🔎", "☑", "⚙"]
private func isToolHeader(_ line: String) -> Bool {
    if line.hasPrefix("$ ") { return true }
    if let f = line.first { return toolPrefixChars.contains(f) }
    return false
}

func parseMessageSegments(_ text: String) -> [MsgSegment] {
    var segs: [MsgSegment] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0
    while i < lines.count {
        let line = lines[i]
        if isToolHeader(line) {
            var body: [String] = []
            var j = i + 1
            while j < lines.count {
                let l = lines[j]
                if l.hasPrefix("+ ") || l.hasPrefix("- ") || l == "…" { body.append(l); j += 1 } else { break }
            }
            var title = line
            if let r = line.range(of: ": ") { title = String(line[r.upperBound...]) }
            else if line.hasPrefix("$ ") { title = String(line.dropFirst(2)) }
            let sym = line.hasPrefix("$ ") ? "$" : String(line.first ?? "⚙")
            segs.append(.tool(ToolBlock(symbol: sym, title: title, bodyLines: body)))
            i = j
        } else {
            var prose = [line]
            var j = i + 1
            while j < lines.count, !isToolHeader(lines[j]) { prose.append(lines[j]); j += 1 }
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segs.append(.prose(joined)) }
            i = j
        }
    }
    return segs
}

/// Mesaj gövdesi — düz metin + açılır-kapanır renkli araç blokları.
struct MessageBody: View {
    let text: String
    var body: some View {
        let segs = parseMessageSegments(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .prose(let p): Text(p).font(.callout)
                case .tool(let t): ToolBlockView(block: t)
                }
            }
        }
    }
}

struct ToolBlockView: View {
    let block: ToolBlock
    @State private var expanded = false

    private var icon: String {
        switch block.symbol {
        case "✎": return "pencil"
        case "＋": return "plus.square"
        case "👁": return "eye"
        case "🔎": return "magnifyingglass"
        case "☑": return "checklist"
        case "$": return "terminal"
        default: return "gearshape"
        }
    }
    private var tint: Color { block.symbol == "$" ? .purple : Color.accentColor }
    private var shortTitle: String {
        // dosya yolundan sadece son parça(lar)ı göster
        let parts = block.title.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        if parts.count >= 2 { return parts.suffix(2).joined(separator: "/") }
        return block.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if block.hasBody { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
            } label: {
                HStack(spacing: 6) {
                    if block.hasBody {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 10)
                    } else {
                        Spacer().frame(width: 10)
                    }
                    Image(systemName: icon).font(.caption).foregroundStyle(tint)
                    Text(shortTitle).font(.system(.caption, design: .monospaced)).lineLimit(1).foregroundStyle(.primary)
                    if block.additions > 0 { Text("+\(block.additions)").font(.caption2).foregroundStyle(.green).monospacedDigit() }
                    if block.deletions > 0 { Text("-\(block.deletions)").font(.caption2).foregroundStyle(.red).monospacedDigit() }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(block.title)

            if expanded && block.hasBody {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(block.bodyLines.enumerated()), id: \.offset) { _, l in
                        Text(l)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(l.hasPrefix("+ ") ? .green : (l.hasPrefix("- ") ? .red : .secondary))
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 20).padding(.top, 3)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "Sen" : "Claude")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                MessageBody(text: message.text)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
