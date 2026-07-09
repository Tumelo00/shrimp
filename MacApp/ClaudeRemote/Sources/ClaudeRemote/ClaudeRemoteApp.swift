import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear {
                    appDelegate.appState = app
                    Notifier.setup()
                    app.connectIfConfigured()
                }
        }
        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tek instance: zaten açık bir Shrimp varsa onu öne getir, bunu kapat (çift pencere olmasın).
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.tumer.clauderemote")
            .filter { $0.processIdentifier != me }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Bağlantılar kapanır → PC'deki watchdog grace süresi sonunda
        // tüm terminalleri kaydedip durdurur.
        appState?.disconnectAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
