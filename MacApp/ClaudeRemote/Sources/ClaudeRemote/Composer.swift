import SwiftUI

// Claude Desktop tarzı seçenekler.
enum ClaudeOptions {
    static let models: [(String, String)] = [
        ("Varsayılan", ""),
        ("Opus 4.8", "opus"),
        ("Sonnet 5", "sonnet"),
        ("Haiku 4.5", "haiku"),
        ("Fable 5", "fable"),
    ]
    static let modes: [(String, String, String)] = [   // (etiket, değer, ikon)
        ("Varsayılan izinler", "default", "hand.raised"),
        ("Edit'leri onayla", "acceptEdits", "checkmark.circle"),
        ("Plan modu", "plan", "list.bullet.clipboard"),
        ("Auto mod", "auto", "wand.and.stars"),
        ("Bypass (izin sorma)", "bypassPermissions", "bolt.shield"),
    ]
    static let efforts = ["", "low", "medium", "high", "xhigh", "max"]  // "" = varsayılan
    static func modelLabel(_ v: String) -> String { models.first { $0.1 == v }?.0 ?? "Model" }
    static func modeLabel(_ v: String) -> String { modes.first { $0.1 == v }?.0 ?? "İzin" }
    static func modeIcon(_ v: String) -> String { modes.first { $0.1 == v }?.2 ?? "hand.raised" }
    static func effortLabel(_ v: String) -> String { v.isEmpty ? "Efor: oto" : "Efor: \(v)" }
    // Pill için kısa mod etiketi (ekran görüntüsündeki gibi)
    static func modeShort(_ v: String) -> String {
        switch v {
        case "bypassPermissions": return "Bypass permissions"
        case "acceptEdits": return "Edit onayı"
        case "plan": return "Plan modu"
        case "auto": return "Auto mod"
        default: return "Varsayılan izinler"
        }
    }
    static func effortShort(_ v: String) -> String { v.isEmpty ? "Oto" : v.capitalized }
}

/// Terminal üstündeki kompozisyon çubuğu — Claude Desktop tarzı: mod pill · + · model · efor · durdur.
struct ComposerBar: View {
    @EnvironmentObject var app: AppState

    private var isBypass: Bool { app.permissionMode == "bypassPermissions" }
    private var hasActive: Bool { app.selectedTerminalID != nil && !app.terminals.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            // İzin modu — pill (bypass = sarı vurgulu)
            Menu {
                ForEach(ClaudeOptions.modes, id: \.1) { m in
                    Button {
                        app.permissionMode = m.1
                        app.emit(.info, "İzin modu", "Yeni terminalde: \(m.0)")
                    } label: {
                        HStack { Image(systemName: m.2); Text(m.0); if app.permissionMode == m.1 { Spacer(); Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: ClaudeOptions.modeIcon(app.permissionMode)).font(.system(size: 10))
                    Text(ClaudeOptions.modeShort(app.permissionMode)).font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(isBypass ? Color.yellow.opacity(0.22) : Color.secondary.opacity(0.14), in: Capsule())
                .foregroundStyle(isBypass ? Color.yellow : Color.primary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            // Görsel/dosya ekle
            Button {
                app.pickAndUploadImage()
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Görsel/dosya ekle (PC'ye yükler, terminale yolunu koyar)")

            Spacer()

            // Model
            Menu {
                ForEach(ClaudeOptions.models, id: \.1) { m in
                    Button {
                        app.applyModelToActive(m.1)
                    } label: {
                        HStack { Text(m.0); if app.selectedModel == m.1 { Spacer(); Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                Text(ClaudeOptions.modelLabel(app.selectedModel)).font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            // Efor (menü — ekran görüntüsündeki "High" gibi)
            Menu {
                ForEach(ClaudeOptions.efforts, id: \.self) { e in
                    Button {
                        app.effort = e
                        app.emit(.info, "Efor", ClaudeOptions.effortLabel(e))
                    } label: {
                        HStack { Text(ClaudeOptions.effortShort(e)); if app.effort == e { Spacer(); Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                Text(ClaudeOptions.effortShort(app.effort)).font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            // Durdur (kırmızı) — çalışan Claude'a ESC gönderir (üretimi keser)
            Button {
                app.sendToActiveTerminal("\u{1b}")
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(hasActive ? Color.red : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!hasActive)
            .help("Çalışan Claude üretimini durdur (ESC)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
    }
}
