import SwiftUI
import SwiftTerm

/// SwiftTerm'in NSView tabanlı terminal emülatörünü SwiftUI'a bağlar.
struct TerminalHostView: NSViewRepresentable {
    let backend: TerminalBackend

    func makeCoordinator() -> Coordinator {
        Coordinator(backend: backend)
    }

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        backend.onData = { [weak tv] data in
            tv?.feed(byteArray: ArraySlice([UInt8](data)))
        }
        backend.flushPending()
        return tv
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}

    final class Coordinator: NSObject, TerminalViewDelegate {
        let backend: TerminalBackend
        init(backend: TerminalBackend) { self.backend = backend }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            backend.sendInput(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            backend.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }

        func bell(source: TerminalView) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
