import Cocoa
import ScreenCaptureKit

// Argüman "full" ise TÜM ekranı, yoksa Shrimp penceresini yakalar → ~/cr-shot.png.
// BİR KEZ derlenip imzalanır; imzası sabit kaldığı için Ekran Kaydı izni kalıcı olur.
let wantFull = CommandLine.arguments.contains("full")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func status(_ s: String) {
    try? s.write(toFile: NSHomeDirectory() + "/cr-shot-status.txt", atomically: true, encoding: .utf8)
}
func save(_ cg: CGImage) {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { status("png-failed"); exit(5) }
    try? data.write(to: URL(fileURLWithPath: NSHomeDirectory() + "/cr-shot.png"))
    status("ok"); exit(0)
}

func capture() async {
    guard #available(macOS 14.0, *) else { status("macos<14"); exit(1) }
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
        status("no-permission"); exit(2)
    }
    if wantFull {
        guard let display = content.displays.first else { status("no-display"); exit(3) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = display.width * 2
        cfg.height = display.height * 2
        cfg.showsCursor = true
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else {
            status("capture-failed"); exit(4)
        }
        save(cg)
    } else {
        guard let win = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.tumer.clauderemote" && $0.frame.width > 400 && $0.frame.height > 300
        }) else { status("no-window"); exit(3) }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let cfg = SCStreamConfiguration()
        cfg.width = Int(win.frame.width * 2)
        cfg.height = Int(win.frame.height * 2)
        cfg.showsCursor = false
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else {
            status("capture-failed"); exit(4)
        }
        save(cg)
    }
}

Task { await capture() }
app.run()
