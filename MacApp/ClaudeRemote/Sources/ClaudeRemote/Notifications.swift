import Foundation
import UserNotifications
import AppKit

/// Uygulama içi bildirim/hata sistemi. macOS push notification + detaylı kod.
enum Notifier {
    private static var authorized = false

    static func setup() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            authorized = ok
        }
    }

    /// Bilgi/hata bildirimi gönder. `code` teknik hata kodu (kullanıcı anlasın diye).
    static func notify(_ title: String, _ body: String, code: String? = nil, sound: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = code != nil ? "\(body)\n[\(code!)]" : body
        if sound { content.sound = .default }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if err != nil || !authorized {
                // bildirim izni yoksa NSUserNotification fallback (deprecated ama çalışır)
                DispatchQueue.main.async { fallback(title, content.body) }
            }
        }
    }

    private static func fallback(_ title: String, _ body: String) {
        let n = NSUserNotification()
        n.title = title
        n.informativeText = body
        NSUserNotificationCenter.default.deliver(n)
    }
}

/// Uygulama içinde geçici gösterilecek hata/olay (toast). AppState yayınlar.
struct AppEvent: Identifiable, Equatable {
    enum Kind { case info, success, warning, error }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let code: String?
    let at: Date
}
