import SwiftUI

/// PC kartı — adına basınca açılır: istatistikler (CPU/RAM/disk) + güç kontrolleri (WOL/restart/uyku).
struct PCCard: View {
    @EnvironmentObject var app: AppState
    @State private var expanded = true

    private var name: String {
        app.stats?.hostname ?? app.pcInfo?.hostname ?? (app.host.isEmpty ? "PC" : app.host)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(app.connected ? .green : .red).frame(width: 9, height: 9)
                    Image(systemName: "desktopcomputer").font(.callout).foregroundStyle(.secondary)
                    Text(name).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let st = app.stats {
                        StatRow(icon: "cpu", label: "CPU", value: st.cpu / 100, text: String(format: "%%%.0f", st.cpu))
                        let used = st.memTotal - st.memFree
                        StatRow(icon: "memorychip", label: "RAM", value: st.memTotal > 0 ? used / st.memTotal : 0,
                                text: "\(fmtBytes(used)) / \(fmtBytes(st.memTotal))")
                        ForEach(st.disks, id: \.drive) { d in
                            let usedD = d.total - d.free
                            StatRow(icon: "internaldrive", label: d.drive, value: d.total > 0 ? usedD / d.total : 0,
                                    text: "\(fmtBytes(d.free)) boş")
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.caption2)
                            Text("Açık: \(fmtUptime(st.uptime))")
                            Spacer()
                            Image(systemName: "terminal").font(.caption2)
                            Text("\(st.terminals ?? 0)")
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(app.connected ? "İstatistik bekleniyor…" : "Bağlanıyor…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !app.connected && app.wakeState == .idle {
                            Button { app.startWake() } label: {
                                Label("PC'yi Uyandır", systemImage: "power").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }

                    Divider()

                    // Güç kontrolleri (Uyandır kaldırıldı — açılışta uyandırma kartı devralır)
                    HStack(spacing: 8) {
                        PowerButton(icon: "arrow.clockwise", label: "Yeniden", tint: .orange) {
                            confirm("PC yeniden başlatılsın mı?") { app.power("restart") }
                        }
                        PowerButton(icon: "moon.fill", label: "Uyku", tint: .blue) {
                            confirm("PC uykuya alınsın mı?") { app.power("sleep") }
                        }
                    }

                    if let note = app.powerNote {
                        Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func confirm(_ msg: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.addButton(withTitle: "Evet")
        alert.addButton(withTitle: "Vazgeç")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: Double
    let text: String

    private var color: Color {
        if value > 0.9 { return .red }
        if value > 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.caption).frame(width: 34, alignment: .leading)
            ProgressView(value: min(max(value, 0), 1)).tint(color)
            Text(text).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing).lineLimit(1)
        }
    }
}

struct PowerButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

/// Claude kullanım kartı — token/maliyet takibi.
struct UsageCard: View {
    @EnvironmentObject var app: AppState
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                if expanded { app.fetchUsage() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.callout).foregroundStyle(Color(red: 0.85, green: 0.5, blue: 0.35))
                    Text("Claude Kullanım").fontWeight(.semibold)
                    Spacer()
                    if let w = app.usage?.window {
                        Text("%\(String(format: "%.0f", w.percent))")
                            .font(.caption).foregroundStyle(usageColor(w.percent)).monospacedDigit()
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)

            // her zaman görünür ince yüzde barı (Claude Desktop gibi)
            if let w = app.usage?.window {
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.18))
                            Capsule().fill(usageColor(w.percent))
                                .frame(width: max(4, geo.size.width * min(1, w.percent / 100)))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 12).padding(.bottom, expanded ? 0 : 10)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let u = app.usage {
                        HStack {
                            Text("Plan kullanım limitleri").font(.caption).foregroundStyle(.secondary)
                            if let plan = u.plan, !plan.isEmpty {
                                Text("· \(plan)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let w = u.window {
                            LimitRow(title: "5 saatlik limit", reset: fmtResetIn(w.resetInSec), percent: w.percent)
                        }
                        if let wk = u.weekly {
                            LimitRow(title: "Haftalık", reset: fmtResetIn(wk.resetInSec), percent: wk.percent)
                        }
                        Divider()
                        let today = u.days.first
                        HStack(spacing: 10) {
                            UsageStat(title: "Bugün", value: today.map { "$\(String(format: "%.2f", $0.cost))" } ?? "—")
                            UsageStat(title: "Toplam", value: "$\(String(format: "%.0f", u.totals.cost))")
                            UsageStat(title: "Mesaj", value: fmtCount(u.totals.messages))
                        }
                        Text("Yüzdeler yerel token tahminidir")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    } else {
                        Text("Yükleniyor…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

func usageColor(_ pct: Double) -> Color {
    if pct >= 90 { return .red }
    if pct >= 70 { return .orange }
    return Color(red: 0.85, green: 0.5, blue: 0.35)   // Claude turuncu
}

/// Claude Desktop tarzı tek limit satırı: başlık + sıfırlanma + yüzde + renkli bar.
struct LimitRow: View {
    let title: String
    let reset: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.caption)
                Spacer()
                if !reset.isEmpty {
                    Text(reset).font(.caption2).foregroundStyle(.secondary)
                }
                Text("%\(String(format: "%.0f", percent))")
                    .font(.caption).monospacedDigit().foregroundStyle(usageColor(percent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(usageColor(percent))
                        .frame(width: max(4, geo.size.width * min(1, percent / 100)))
                }
            }
            .frame(height: 6)
        }
    }
}

struct UsageStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.callout).fontWeight(.semibold).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
