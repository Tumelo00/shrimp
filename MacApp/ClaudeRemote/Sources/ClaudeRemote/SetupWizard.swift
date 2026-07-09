import SwiftUI

/// Windows agent'ın GitHub deposu + tek-komut kurulum satırı.
let SHRIMP_AGENT_REPO = "https://github.com/Tumelo00/shrimp"
let SHRIMP_AGENT_INSTALL = "irm https://raw.githubusercontent.com/Tumelo00/shrimp/main/agent/install.ps1 | iex"

/// Açılış kurulum sihirbazı — 4 adım: Agent · Eşleştir · Yetkilendir · Hazır.
/// Arkadaki Shrimp menüsünü blur'lar, ortada temalı kart gösterir.
struct SetupWizardView: View {
    @EnvironmentObject var app: AppState
    @State private var step = 0
    @State private var pairingCode = ""
    @State private var showManual = false

    private let titles = ["Windows Agent", "Eşleştir", "Claude Yetki", "Hazır"]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.30).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                content.padding(20).frame(minHeight: 240, alignment: .top)
                Divider().opacity(0.25)
                footer.padding(14)
            }
            .frame(width: 470)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        }
        .onChange(of: app.connected) { c in if c && step == 1 { advance() } }
        .onAppear { app.refreshHealthToken() }
    }

    // MARK: header
    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("Shrimp Kurulumu").font(.headline)
                Text("Adım \(step + 1)/4 · \(titles[step])").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<4) { i in
                    Circle().fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: content
    @ViewBuilder private var content: some View {
        switch step {
        case 0: agentStep
        case 1: pairStep
        case 2: authStep
        default: doneStep
        }
    }

    private var agentStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Windows PC'ne agent kur", systemImage: "desktopcomputer.and.arrow.down").font(.title3).bold()
            Text("Shrimp, Windows PC'ndeki küçük bir 'agent' üzerinden çalışır. PC'de PowerShell'i **Yönetici olarak** aç ve şunu yapıştır:")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(SHRIMP_AGENT_INSTALL)
                    .font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                Button { copyText(SHRIMP_AGENT_INSTALL) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("Kopyala")
            }
            Text("Node.js + agent'ı kurar, otomatik başlatır ve sana bir eşleştirme kodu verir (sonraki adımda gireceksin).")
                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: SHRIMP_AGENT_REPO)!) { Label("Repo / detaylar (GitHub)", systemImage: "link") }.font(.caption)
        }
    }

    private func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var pairStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Eşleştirme kodunu gir", systemImage: "number.circle.fill").font(.title3).bold()
            Text("PC'de açılan pencerede **6 haneli** bir kod var. Onu gir ve Bağlan'a bas.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("6 haneli kod", text: $pairingCode)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center).padding(.vertical, 10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { app.applyPairingCode(pairingCode) }
            if let e = app.pairingError { Text(e).font(.caption).foregroundStyle(.red) }
            if app.connected { Label("Bağlandı", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            Button("Manuel (IP · port · token)") { withAnimation { showManual.toggle() } }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            if showManual {
                VStack(spacing: 6) {
                    TextField("Tailscale IP", text: $app.host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $app.portText).textFieldStyle(.roundedBorder)
                    SecureField("Token", text: $app.token).textFieldStyle(.roundedBorder)
                    Button("Bağlan") { app.connect() }.controlSize(.small)
                }
                .font(.caption)
            }
        }
    }

    private var authStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Claude hesabını yetkilendir", systemImage: "sparkles").font(.title3).bold()
            Text("Native sohbet (uygulama içi Claude) için hesabını bir kez yetkilendir. Bu, PC'de uzun-ömürlü bir oturum anahtarı üretir.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if app.hasClaudeToken {
                Label("Zaten yetkili — native sohbet hazır", systemImage: "checkmark.seal.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if app.authRunning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Yetkilendiriliyor… (PC'de tarayıcı onayı gerekebilir)").font(.callout).foregroundStyle(.secondary) }
            } else {
                Button { app.runSetupToken() } label: { Label("Yetkilendir", systemImage: "key.fill") }
                    .buttonStyle(.borderedProminent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Otomatik çalışmazsa (agent arka planda tarayıcı açamaz): PC'de bir terminalde şunu çalıştır:")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("claude setup-token")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    Text("Tarayıcıdan onayla; token PC'ye kaydolur. Bu adımı atlayabilirsin (terminalden Claude yine çalışır).")
                        .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
            Text("Hazırsın! 🦐").font(.title2).bold()
            Text("Shrimp kuruldu ve bağlandı. Artık PC'ni uzaktan yönetebilir, Claude ile çalışabilirsin.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    // MARK: footer
    private var footer: some View {
        HStack {
            if step > 0 && step < 3 {
                Button("Geri") { back() }.buttonStyle(.bordered)
            }
            if step == 2 { Button("Atla") { advance() }.buttonStyle(.plain).foregroundStyle(.secondary) }
            Spacer()
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0:
            Button("Devam") { advance() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case 1:
            Button("Bağlan") { app.applyPairingCode(pairingCode) }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(pairingCode.trimmingCharacters(in: .whitespaces).isEmpty)
        case 2:
            Button(app.hasClaudeToken ? "Devam" : "Devam") { advance() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(app.authRunning)
        default:
            Button("Başla") { finish() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.2)) { step = min(step + 1, 3) } }
    private func back() { withAnimation(.easeInOut(duration: 0.2)) { step = max(step - 1, 0) } }
    private func finish() { app.setupComplete = true; app.showSetupWizard = false }
}
