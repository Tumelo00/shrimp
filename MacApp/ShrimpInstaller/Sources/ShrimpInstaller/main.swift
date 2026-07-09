import SwiftUI
import AppKit

// Shrimp.app'in indirileceği GitHub Release (her zaman en son sürüm).
let SHRIMP_ZIP_URL = "https://github.com/Tumelo00/shrimp/releases/latest/download/Shrimp.zip"
let TAILSCALE_DL   = "https://tailscale.com/download/mac"

struct Err: LocalizedError { let m: String; init(_ m: String) { self.m = m }; var errorDescription: String? { m } }

// MARK: - Installer motoru

@MainActor
final class Installer: ObservableObject {
    enum Phase: Equatable { case welcome, working, needTailscale, done, failed }
    @Published var phase: Phase = .welcome
    @Published var message = ""
    @Published var errorText = ""
    @Published var tailscaleOK = false

    func start() { phase = .working; Task { await run() } }

    private func run() async {
        do {
            message = "Shrimp indiriliyor…"
            let zip = try await download(SHRIMP_ZIP_URL)
            message = "Kuruluyor…"
            try install(zip: zip)
            message = "Tailscale kontrol ediliyor…"
            tailscaleOK = tailscaleInstalled()
            phase = tailscaleOK ? .done : .needTailscale
            message = tailscaleOK ? "Hazır!" : "Tailscale gerekli"
        } catch {
            errorText = error.localizedDescription
            phase = .failed
        }
    }

    private func download(_ s: String) async throws -> URL {
        guard let url = URL(string: s) else { throw Err("Geçersiz indirme adresi") }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw Err("İndirme başarısız (HTTP \(http.statusCode))") }
        return tmp
    }

    private func install(zip: URL) throws {
        let dest = URL(fileURLWithPath: "/Applications/Shrimp.app")
        let unzip = FileManager.default.temporaryDirectory.appendingPathComponent("shrimp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unzip, withIntermediateDirectories: true)
        try sh("/usr/bin/ditto", ["-x", "-k", zip.path, unzip.path])
        let src = unzip.appendingPathComponent("Shrimp.app")
        guard FileManager.default.fileExists(atPath: src.path) else { throw Err("İndirilen paket içinde Shrimp.app yok") }
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: src, to: dest)
        _ = try? sh("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])  // imzasız app açılabilsin
        try? FileManager.default.removeItem(at: unzip)
    }

    private func tailscaleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Tailscale.app") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/tailscale") ||
        FileManager.default.fileExists(atPath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    }

    func openTailscaleDownload() { if let u = URL(string: TAILSCALE_DL) { NSWorkspace.shared.open(u) } }

    /// Shrimp'i başlat + DMG'yi eject edip .dmg dosyasını sil (çöp bırakma) + kapan.
    func launchAndCleanup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Shrimp.app"))
        let script = """
        sleep 3
        for v in /Volumes/Shrimp*; do /usr/bin/hdiutil detach "$v" -force >/dev/null 2>&1; done
        rm -f "$HOME/Downloads/Shrimp"*.dmg "$HOME/Desktop/Shrimp"*.dmg 2>/dev/null
        rm -rf "/Applications/Shrimp Kurulum.app" "$HOME/Applications/Shrimp Kurulum.app" 2>/dev/null
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    @discardableResult
    private func sh(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw Err("\(path.split(separator: "/").last ?? "") hata: \(out)") }
        return out
    }
}

// MARK: - Görünüm

struct InstallerView: View {
    @StateObject private var inst = Installer()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            Text("Shrimp Kurulumu").font(.title2).bold()
            content
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 420, height: 360)
        .background(bg)
    }

    private var bg: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.03, green: 0.05, blue: 0.10)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch inst.phase {
        case .welcome:
            VStack(spacing: 14) {
                Text("Shrimp'i bilgisayarına kuralım. Uygulama indirilecek ve /Applications'a yerleştirilecek.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { inst.start() } label: { Text("Kur").frame(width: 160) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        case .working:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(inst.message).font(.callout).foregroundStyle(.secondary)
            }
        case .needTailscale:
            VStack(spacing: 12) {
                Image(systemName: "network").font(.system(size: 28)).foregroundStyle(.orange)
                Text("Shrimp, PC'ne Tailscale ile bağlanır. Tailscale kurulu değil.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { inst.openTailscaleDownload() } label: { Label("Tailscale'i indir", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent)
                Button("Kurdum, devam") { inst.phase = .done }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            }
        case .done:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
                Text("Hazırız! 🦐").font(.headline)
                Text("Shrimp kuruldu. Başlat'a basınca uygulama açılır ve bu kurulum aracı temizlenir.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { inst.launchAndCleanup() } label: { Text("Shrimp'i Başlat").frame(width: 180) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.red)
                Text("Kurulum başarısız").font(.headline)
                Text(inst.errorText).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tekrar dene") { inst.start() }.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - App

struct ShrimpInstallerApp: App {
    var body: some Scene {
        WindowGroup { InstallerView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}

// SwiftPM executable giriş noktası
ShrimpInstallerApp.main()
