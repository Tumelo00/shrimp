import SwiftUI

/// Üst bilgi çubuğu: bağlantı durumu + PC istatistikleri (WS push ile gelir, polling yok).
struct StatsBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle()
                    .fill(app.connected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(app.stats?.hostname ?? app.host)
                    .fontWeight(.medium)
            }

            if let st = app.stats {
                MiniGauge(label: "CPU", value: st.cpu / 100,
                          text: String(format: "%%%.0f", st.cpu))

                let used = st.memTotal - st.memFree
                MiniGauge(label: "RAM", value: st.memTotal > 0 ? used / st.memTotal : 0,
                          text: fmtBytes(used) + " / " + fmtBytes(st.memTotal))

                ForEach(st.disks, id: \.drive) { d in
                    let usedD = d.total - d.free
                    MiniGauge(label: d.drive, value: d.total > 0 ? usedD / d.total : 0,
                              text: fmtBytes(d.free) + " boş")
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text(fmtUptime(st.uptime))
                }
                .foregroundStyle(.secondary)

                if let t = st.terminals {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal").font(.caption2)
                        Text("\(t)")
                    }
                    .foregroundStyle(.secondary)
                    .help("PC'de çalışan terminal sayısı")
                }
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct MiniGauge: View {
    let label: String
    let value: Double
    let text: String

    private var color: Color {
        if value > 0.9 { return .red }
        if value > 0.7 { return .orange }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            ProgressView(value: min(max(value, 0), 1))
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: 56)
            Text(text).monospacedDigit()
        }
    }
}
