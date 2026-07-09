import Foundation

struct ProjectInfo: Codable, Identifiable, Hashable {
    var dir: String
    var name: String
    var path: String
    var sessionCount: Int
    var lastModified: Double
    var id: String { dir }
}

struct ProjectsResponse: Codable { var projects: [ProjectInfo] }

struct SessionInfo: Codable, Identifiable, Hashable {
    var id: String
    var summary: String
    var mtime: Double
    var size: Double
}

struct SessionsResponse: Codable { var sessions: [SessionInfo] }

// Claude Desktop tarzı düz oturum (Recents + pinned)
struct DesktopSession: Codable, Identifiable, Hashable {
    var id: String            // cliSessionId
    var title: String
    var cwd: String
    var slug: String?
    var lastActivityAt: Double
    var pinned: Bool
}
struct DesktopSessionsResponse: Codable { var sessions: [DesktopSession] }

struct ChatMessage: Codable, Hashable {
    var role: String
    var text: String
    var ts: String
}

struct ChatPage: Codable {
    var total: Int
    var start: Int
    var messages: [ChatMessage]
}

struct TerminalInfo: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var cwd: String
    var mode: String
    var createdAt: String?
    var savedAt: String?
    var active: Bool
    var clients: Int?
}

struct TerminalListResponse: Codable {
    var active: [TerminalInfo]
    var saved: [TerminalInfo]
}

struct CreatedTerminal: Codable {
    var id: String
    var title: String
    var cwd: String
    var mode: String
}

struct DiskInfo: Codable, Hashable {
    var drive: String
    var total: Double
    var free: Double
}

struct StatsSnapshot: Codable {
    var cpu: Double
    var memTotal: Double
    var memFree: Double
    var uptime: Double
    var hostname: String
    var disks: [DiskInfo]
    var terminals: Int?
}

struct FileEntry: Codable, Identifiable, Hashable {
    var name: String
    var dir: Bool
    var size: Double
    var mtime: Double
    var id: String { name }
}

struct FileListing: Codable {
    var path: String
    var truncated: Bool?
    var entries: [FileEntry]
}

struct FileContent: Codable {
    var path: String
    var size: Double
    var binary: Bool
    var truncated: Bool?
    var content: String
}

struct HealthResponse: Codable { var ok: Bool; var hasClaudeToken: Bool? }
struct SetupTokenResp: Codable { var ok: Bool; var error: String? }
struct OkResponse: Codable { var ok: Bool? }
struct SaveStopResponse: Codable { var saved: Int }

struct PCInfo: Codable {
    var hostname: String
    var mac: String?
    var lanIP: String?
    var iface: String?
}

struct PowerResponse: Codable {
    var ok: Bool?
    var action: String?
    var error: String?
}

struct UsageBucket: Codable, Hashable {
    var input: Double
    var output: Double
    var cacheWrite: Double
    var cacheRead: Double
    var messages: Double
    var cost: Double
}

struct UsageDay: Codable, Hashable, Identifiable {
    var date: String
    var input: Double
    var output: Double
    var cacheWrite: Double
    var cacheRead: Double
    var messages: Double
    var cost: Double
    var id: String { date }
}

struct UsageWindow: Codable {
    var input: Double
    var output: Double
    var cacheWrite: Double
    var cacheRead: Double
    var messages: Double
    var used: Double
    var limit: Double
    var percent: Double
    var windowHours: Double?
    var resetInSec: Double?
}

struct Usage: Codable {
    var totals: UsageBucket
    var days: [UsageDay]
    var files: Int
    var window: UsageWindow?
    var weekly: UsageWindow?
    var plan: String?
}

/// "4 sa 1 dk sonra" biçiminde sıfırlanma metni.
func fmtResetIn(_ sec: Double?) -> String {
    guard let s = sec, s > 0 else { return "" }
    let total = Int(s)
    let h = total / 3600, m = (total % 3600) / 60
    if h >= 24 { let d = h / 24; return "\(d) gün \(h % 24) sa sonra" }
    if h > 0 { return "\(h) sa \(m) dk sonra" }
    return "\(m) dk sonra"
}

func fmtCount(_ v: Double) -> String {
    if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1e9) }
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1e6) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1e3) }
    return String(format: "%.0f", v)
}

/// Native chat hedefi — yeni sohbet (hepsi nil) ya da eski oturumu devam (resume+slug+cwd).
/// `id` görünüm kimliğini belirler: her yeni sohbet taze id → taze ChatSession.
struct ChatTarget: Hashable {
    var id: String = UUID().uuidString
    var resume: String? = nil     // devam edilecek oturum id'si
    var slug: String? = nil       // proje dizini (geçmişi yüklemek için)
    var cwd: String? = nil        // gerçek çalışma dizini (claude burada koşar)
    var title: String? = nil
}

enum SidebarSelection: Hashable {
    case terminals
    case files
    case chat(String, String) // (projectDir, sessionID)
    case nativeChat(ChatTarget)
}

func fmtBytes(_ v: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var x = v, i = 0
    while x >= 1024 && i < units.count - 1 { x /= 1024; i += 1 }
    return String(format: i == 0 ? "%.0f %@" : "%.1f %@", x, units[i])
}

func fmtUptime(_ seconds: Double) -> String {
    let s = Int(seconds)
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)g \(h)s" }
    if h > 0 { return "\(h)s \(m)dk" }
    return "\(m)dk"
}

func fmtDate(_ epochMs: Double) -> String {
    let df = DateFormatter()
    df.dateFormat = "d MMM HH:mm"
    df.locale = Locale(identifier: "tr_TR")
    return df.string(from: Date(timeIntervalSince1970: epochMs / 1000))
}
