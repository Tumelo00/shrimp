import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        } detail: {
            detailView
                .navigationTitle("Shrimp")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Section("Claude Code — proje seç") {
                        ForEach(app.projects) { p in
                            Button(p.name) { app.quickStartClaude(project: p) }
                        }
                    }
                    Divider()
                    Button("PowerShell") { app.newTerminal(cwd: nil, mode: "shell") }
                } label: {
                    Label("Claude Başlat", systemImage: "plus")
                } primaryAction: {
                    app.quickStartClaude()   // tek tık: varsayılan dizinde Claude
                }
                .menuStyle(.button)
                .disabled(!app.connected)

                Button {
                    app.saveStopAll()
                } label: {
                    Label("Kaydet & Durdur", systemImage: "stop.circle")
                }
                .help("PC'deki tüm terminalleri kaydedip durdurur")
                .disabled(app.terminals.isEmpty && app.remoteActive.isEmpty)
            }
        }
        .overlay {
            // Açılışta PC uykudaysa: blur'lu uyandırma kartı (Shrimp menüsü arkada kalır).
            if app.wakeState != .idle { WakeCardView() }
        }
        .overlay {
            // Gömülü Tailscale login gerekiyorsa (resmi Tailscale yok): giriş kartı.
            if app.tsnetAuthURL != nil && !app.connected { TsnetLoginOverlay() }
        }
        .overlay {
            // Kurulmamış (ilk açılış) ya da yeniden açıldıysa: kurulum sihirbazı (en üstte).
            if !app.setupComplete || app.showSetupWizard {
                SetupWizardView()
            }
        }
        .overlay(alignment: .topTrailing) {
            ToastStack()
                .padding(.top, 52).padding(.trailing, 12)   // composer bar'ın altında
        }
        .task {
            // İlk bağlanmaya kısa şans ver; hâlâ bağlı değilse uyandırma kartını aç.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            app.autoWakeIfNeeded()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch app.selection {
        case .chat(let project, let session):
            ChatHistoryView(project: project, sessionID: session)
        case .nativeChat(let target):
            NativeChatView(app: app, target: target)
                .id(target.id)
        case .files:
            FileBrowserView()
        default:
            TerminalAreaView()
        }
    }
}

// MARK: - Bağlantı ekranı

struct ConnectOverlay: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "desktopcomputer.and.macbook")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("PC'ye Bağlan").font(.title2).bold()

            Form {
                TextField("Tailscale IP", text: $app.host, prompt: Text("100.x.x.x"))
                TextField("Port", text: $app.portText)
                SecureField("Token", text: $app.token)
            }
            .frame(width: 320)

            if let err = app.lastError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Text("Token, PC'de %USERPROFILE%\\.claude-remote\\config.json içinde")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Bağlan") { app.connect() }
                .keyboardShortcut(.defaultAction)
                .disabled(app.host.isEmpty || app.token.isEmpty)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
    }
}

// MARK: - Toast (uygulama içi hata/olay bildirimleri)

struct ToastStack: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(app.events) { ev in
                ToastRow(event: ev)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.events)
        .frame(maxWidth: 340, alignment: .trailing)
    }
}

struct ToastRow: View {
    @EnvironmentObject var app: AppState
    let event: AppEvent

    private var icon: String {
        switch event.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    private var tint: Color {
        switch event.kind {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.callout).fontWeight(.semibold)
                Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                if let code = event.code {
                    Text(code).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button {
                app.events.removeAll { $0.id == event.id }
            } label: { Image(systemName: "xmark").font(.system(size: 9)) }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.4)))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .frame(width: 320)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            PCCard()
            UsageCard()
            sidebarList
        }
    }

    private var sidebarList: some View {
        List(selection: $app.selection) {
            Section("Genel") {
                // Buton: her tıklamada TAZE ChatTarget (yeni id) → yeni bağımsız sohbet.
                Button { app.newNativeChat() } label: {
                    Label("Yeni Sohbet", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Label("Terminaller", systemImage: "terminal")
                    .tag(SidebarSelection.terminals)
                Label("Dosya Gezgini", systemImage: "folder")
                    .tag(SidebarSelection.files)
            }

            if !app.remoteActive.isEmpty || !app.savedTerminals.isEmpty {
                Section("PC'deki Oturumlar") {
                    ForEach(app.remoteActive) { t in
                        Button {
                            app.attachTerminal(id: t.id, title: t.title)
                        } label: {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 7))
                                Text(t.title).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(app.savedTerminals) { t in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(t.title).lineLimit(1)
                                Text("kayıtlı").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Devam") {
                                app.newTerminal(cwd: nil, mode: t.mode, resumeSaved: t.id)
                            }
                            .font(.caption)
                        }
                        .contextMenu {
                            Button("Kaydı Sil", role: .destructive) { app.deleteSaved(t.id) }
                        }
                    }
                }
            }

            // Claude Desktop gibi DÜZ liste: Sabitlenenler + Sohbetler (gruplama yok)
            if !app.pinnedSessions.isEmpty {
                Section("Sabitlenenler") {
                    ForEach(app.pinnedSessions) { s in DesktopSessionRow(session: s) }
                }
            }
            Section("Sohbetler") {
                if app.recentSessions.isEmpty {
                    Text("Sohbet yok").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(app.recentSessions) { s in DesktopSessionRow(session: s) }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            app.connect()
        }
    }

    struct DesktopSessionRow: View {
        @EnvironmentObject var app: AppState
        let session: DesktopSession

        var body: some View {
            HStack(spacing: 6) {
                if app.pinnedIDs.contains(session.id) {
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.orange)
                }
                Text(session.title.isEmpty ? String(session.id.prefix(8)) : session.title)
                    .lineLimit(1).font(.callout)
                Spacer(minLength: 0)
                Button {
                    app.resumeDesktopSession(session)
                } label: {
                    Image(systemName: "play.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Bu sohbeti terminalde devam ettir")
            }
            .contentShape(Rectangle())
            .onTapGesture { app.selection = .nativeChat(targetFor(session)) }
            .contextMenu {
                Button(app.pinnedIDs.contains(session.id) ? "Sabitlemeyi kaldır" : "Sabitle",
                       systemImage: "pin") { app.togglePin(session.id) }
                Divider()
                Button("Sohbete Devam", systemImage: "sparkles") {
                    app.selection = .nativeChat(targetFor(session))
                }
                Button("Terminalde Devam", systemImage: "play.fill") { app.resumeDesktopSession(session) }
                Button("Geçmişi Görüntüle (salt-okunur)", systemImage: "clock") { app.viewDesktopSession(session) }
            }
        }

        private func targetFor(_ s: DesktopSession) -> ChatTarget {
            ChatTarget(id: "resume-\(s.id)", resume: s.id, slug: s.slug,
                       cwd: s.cwd.isEmpty ? nil : s.cwd,
                       title: s.title.isEmpty ? nil : s.title)
        }
    }

    private func expandBinding(_ proj: ProjectInfo) -> Binding<Bool> {
        Binding(
            get: { app.expandedProjects.contains(proj.dir) },
            set: { open in
                if open {
                    app.expandedProjects.insert(proj.dir)
                    if app.sessionsByProject[proj.dir] == nil {
                        app.loadSessions(proj.dir)
                    }
                } else {
                    app.expandedProjects.remove(proj.dir)
                }
            }
        )
    }
}

// MARK: - Terminal alanı (sekmeli)

struct TerminalAreaView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ComposerBar()          // Model · İzin · Efor · Görsel ekle
            Divider()
            if app.terminals.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Açık terminal yok").foregroundStyle(.secondary)
                    Menu {
                        Section("Proje seç") {
                            ForEach(app.projects) { p in
                                Button(p.name) { app.quickStartClaude(project: p) }
                            }
                        }
                        Divider()
                        Button("PowerShell") { app.newTerminal(cwd: nil, mode: "shell") }
                    } label: {
                        Label("Claude Başlat", systemImage: "sparkle")
                    } primaryAction: {
                        app.quickStartClaude()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(!app.connected)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Sekme çubuğu
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(app.terminals) { tab in
                            TabChip(tab: tab, selected: tab.id == app.selectedTerminalID)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(.bar)
                Divider()

                if let sel = app.terminals.first(where: { $0.id == app.selectedTerminalID }) ?? app.terminals.last {
                    TerminalHostView(backend: sel.backend)
                        .id(sel.id)
                        .background(Color.black)
                }
            }
        }
    }
}

struct TabChip: View {
    @EnvironmentObject var app: AppState
    let tab: TerminalTab
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.title.hasPrefix("claude") ? "sparkle" : "terminal")
                .font(.caption)
            Text(tab.title).font(.callout).lineLimit(1)
            Button {
                app.detachTab(tab.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help("Sekmeyi kapat (PC'de çalışmaya devam eder)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { app.selectedTerminalID = tab.id }
        .contextMenu {
            Button("Sekmeyi Kapat (süreç devam eder)") { app.detachTab(tab.id) }
            Button("Süreci Sonlandır", role: .destructive) { app.killTerminal(tab.id) }
        }
    }
}
