import Foundation

/// PC'deki bir PTY oturumuna açılan WebSocket köprüsü.
/// Binary çerçeve = terminal G/Ç; text JSON = kontrol mesajı.
final class TerminalBackend {
    let id: String
    let title: String

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pending = Data() // görünüm bağlanmadan gelen veri
    private(set) var isOpen = false

    /// Ana thread'de çağrılır; SwiftTerm görünümüne veri basar.
    var onData: ((Data) -> Void)? {
        didSet { flushPending() }
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    func connect(url: URL) {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        let s = URLSession(configuration: cfg)
        session = s
        let t = s.webSocketTask(with: url)
        t.maximumMessageSize = 8 * 1024 * 1024
        task = t
        isOpen = true
        t.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    if self.isOpen {
                        self.isOpen = false
                        self.deliver(Data("\r\n\u{1b}[2m[bağlantı koptu]\u{1b}[0m\r\n".utf8))
                    }
                }
            case .success(let msg):
                switch msg {
                case .data(let d):
                    DispatchQueue.main.async { self.deliver(d) }
                case .string(let s):
                    DispatchQueue.main.async { self.handleControl(s) }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func deliver(_ d: Data) {
        if let onData { onData(d) } else { pending.append(d) }
    }

    func flushPending() {
        guard let onData, !pending.isEmpty else { return }
        let d = pending
        pending = Data()
        onData(d)
    }

    private func handleControl(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        if type == "exit" {
            deliver(Data("\r\n\u{1b}[2m[oturum sonlandı]\u{1b}[0m\r\n".utf8))
        }
    }

    func sendInput(_ data: Data) {
        guard isOpen else { return }
        task?.send(.data(data)) { _ in }
    }

    func sendResize(cols: Int, rows: Int) {
        guard isOpen, cols > 0, rows > 0 else { return }
        task?.send(.string("{\"type\":\"resize\",\"cols\":\(cols),\"rows\":\(rows)}")) { _ in }
    }

    func close() {
        isOpen = false
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }
}

/// İstatistik yayını: sunucu abone olunca 2sn'de bir push eder; kopunca 5sn'de bir yeniden dener.
final class StatsSocket {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var url: URL?
    private var active = false

    var onStats: ((StatsSnapshot) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    func start(url: URL) {
        stop()
        self.url = url
        active = true
        open()
    }

    private func open() {
        guard active, let url else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, self.active else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { self.onConnectionChange?(false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.open() }
            case .success(let msg):
                if case .string(let s) = msg,
                   let d = s.data(using: .utf8),
                   let snap = try? JSONDecoder().decode(StatsSnapshot.self, from: d) {
                    DispatchQueue.main.async {
                        self.onConnectionChange?(true)
                        self.onStats?(snap)
                    }
                }
                self.receive()
            }
        }
    }

    func stop() {
        active = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
