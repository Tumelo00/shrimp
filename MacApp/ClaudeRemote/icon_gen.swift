import AppKit
import CoreGraphics

// Mavi pixel-art karides, beyaz zemin — keskin (Claude-logo gibi flat pixeller).
// Vektör karidesi doğrudan GRIDxGRID CGContext'e çiz (AA on) → buffer'ı oku →
// palete snap (beyaz-eğilimli, ince kalsın) → keskin blok olarak büyüt.

let GRID = 50
let OUT = 1050.0                     // 50*21

struct C3 { var r: Double; var g: Double; var b: Double }
let cBlue  = C3(r: 0.13, g: 0.45, b: 0.95)
let cDark  = C3(r: 0.05, g: 0.22, b: 0.62)
let cLight = C3(r: 0.55, g: 0.75, b: 1.0)
let colored = [cBlue, cDark, cLight]

// --- 1) shrimp'i GRID çözünürlükte CGContext'e çiz (origin sol-ALT, y yukarı) ---
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: GRID, height: GRID, bitsPerComponent: 8,
                          bytesPerRow: GRID * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high
let sc = Double(GRID) / 1024.0                    // 1024-uzayından GRID'e ölçek
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x*sc, y: y*sc) }
func setFill(_ c: C3) { ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
func setStroke(_ c: C3) { ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
func disk(_ ct: CGPoint, _ r: Double, _ c: C3) {
    setFill(c); ctx.fillEllipse(in: CGRect(x: ct.x - r*sc, y: ct.y - r*sc, width: 2*r*sc, height: 2*r*sc))
}
func bez(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                   y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
}

// beyaz zemin
ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: GRID, height: GRID))

// omurga (kafa sol-üst → aşağı kıvrıl → kuyruk sağ-üst) — y yukarı olduğundan üst=büyük y
let head = p(300, 470), c1 = p(150, 880), c2 = p(780, 930), tail = p(800, 500)
let rMax = 120.0, rMin = 26.0
let N = 120
for i in 0...N {
    let t = Double(i)/Double(N)
    disk(bez(head, c1, c2, tail, t), rMax*(1-t) + rMin*t, cBlue)
}
// segmentler (dik koyu şeritler)
ctx.setLineCap(.round)
for k in stride(from: 0.32, through: 0.86, by: 0.11) {
    let pt = bez(head, c1, c2, tail, k)
    let pa = bez(head, c1, c2, tail, max(0, k-0.02)), pb = bez(head, c1, c2, tail, min(1, k+0.02))
    let tx = pb.x-pa.x, ty = pb.y-pa.y, len = max(1e-4, (tx*tx+ty*ty).squareRoot())
    let nx = -ty/len, ny = tx/len, r = (rMax*(1-k) + rMin*k)*sc
    setStroke(cDark); ctx.setLineWidth(16*sc)
    ctx.move(to: CGPoint(x: pt.x - nx*r*0.7, y: pt.y - ny*r*0.7))
    ctx.addLine(to: CGPoint(x: pt.x + nx*r*0.7, y: pt.y + ny*r*0.7)); ctx.strokePath()
}
// kuyruk yelpazesi
let tp = bez(head, c1, c2, tail, 1.0)
func triFan(_ tip: CGPoint, _ ang: Double, _ len: Double, _ w: Double) {
    let a = ang * .pi/180, dx = cos(a), dy = sin(a), nxx = -sin(a), nyy = cos(a)
    let end = CGPoint(x: tip.x + dx*len*sc, y: tip.y + dy*len*sc)
    setFill(cBlue)
    ctx.move(to: tip)
    ctx.addLine(to: CGPoint(x: end.x + nxx*w*sc, y: end.y + nyy*w*sc))
    ctx.addLine(to: CGPoint(x: end.x - nxx*w*sc, y: end.y - nyy*w*sc))
    ctx.closePath(); ctx.fillPath()
}
// kuyruk üstte (y büyük yön) → açılar yukarı
triFan(tp, -55, 190, 66); triFan(tp, -88, 210, 62); triFan(tp, -120, 185, 62)
// kafa + göz
disk(head, rMax, cBlue)
disk(p(280, 420), 30, C3(r: 1, g: 1, b: 1))
disk(p(286, 420), 13, cDark)
// antenler (kafadan sol-üst)
setStroke(cDark); ctx.setLineWidth(16*sc)
ctx.move(to: p(250, 400)); ctx.addQuadCurve(to: p(70, 60), control: p(120, 180)); ctx.strokePath()
ctx.move(to: p(235, 430)); ctx.addQuadCurve(to: p(40, 380), control: p(90, 320)); ctx.strokePath()
// bacaklar (karnın altında)
for k in stride(from: 0.40, through: 0.70, by: 0.10) {
    let pt = bez(head, c1, c2, tail, k), r = (rMax*(1-k) + rMin*k)*sc
    setStroke(cDark); ctx.setLineWidth(12*sc)
    ctx.move(to: CGPoint(x: pt.x, y: pt.y + r*0.6)); ctx.addLine(to: CGPoint(x: pt.x - 6*sc, y: pt.y + r + 26*sc)); ctx.strokePath()
}
disk(p(430, 610), 34, cLight)

// --- 2) buffer'ı oku (row 0 = ALT, çünkü origin sol-alt) ---
guard let buf = ctx.data else { exit(1) }
let ptr = buf.bindMemory(to: UInt8.self, capacity: GRID * GRID * 4)
func px(_ col: Int, _ row: Int) -> C3 {
    let o = (row * GRID + col) * 4
    return C3(r: Double(ptr[o])/255, g: Double(ptr[o+1])/255, b: Double(ptr[o+2])/255)
}
func snap(_ c: C3) -> C3? {
    if min(c.r, c.g, c.b) > 0.74 { return nil }        // açık/beyaz kenar → zemin (ince tut)
    var best = cBlue; var bd = 1e9
    for cc in colored {
        let d = (cc.r-c.r)*(cc.r-c.r) + (cc.g-c.g)*(cc.g-c.g) + (cc.b-c.b)*(cc.b-c.b)
        if d < bd { bd = d; best = cc }
    }
    return best
}

// --- 3) keskin blok olarak büyüt + beyaz squircle (row 0 = alt → output y = row*cell) ---
let cell = OUT / Double(GRID)
let img = NSImage(size: NSSize(width: OUT, height: OUT))
img.lockFocus()
let g = NSGraphicsContext.current!; g.cgContext.setShouldAntialias(false)
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: OUT, height: OUT), xRadius: OUT*0.22, yRadius: OUT*0.22)
NSColor.white.setFill(); bg.fill(); bg.setClip()
for row in 0..<GRID {
    for col in 0..<GRID {
        guard let c = snap(px(col, row)) else { continue }
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: Double(col)*cell, y: Double(row)*cell, width: cell+0.5, height: cell+0.5)).fill()
    }
}
img.unlockFocus()

guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "shrimp.png"
try! png.write(to: URL(fileURLWithPath: out))
print("yazildi: \(out)")
