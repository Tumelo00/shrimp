import SwiftUI

/// Uyandırma akışı durumu.
enum WakeState: Equatable {
    case idle          // kart yok
    case waking        // WOL/ntfy sinyalleri gidiyor, PC bekleniyor
    case verifying     // PC yanıt verdi, bağlanılıyor
    case connected     // bağlandı (kısa "tamam" anı)
    case failed        // süre doldu, uyandırılamadı
}

/// Açılışta PC uykudaysa: arkadaki Shrimp menüsünü blur'layan, ortada uyandırma kartı.
struct WakeCardView: View {
    @EnvironmentObject var app: AppState
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Arka planı blur'la (Shrimp menüsü arkada kalır, karartılıp bulanır)
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.28).ignoresSafeArea()

            card
                .frame(width: 340)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.25), value: app.wakeState)
    }

    @ViewBuilder
    private var card: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 6) {
                Text(title).font(.title3).fontWeight(.semibold)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if app.wakeState == .waking || app.wakeState == .verifying {
                ProgressView().controlSize(.small)
                Text("Deneme \(app.wakeAttempts)").font(.caption2).foregroundStyle(.tertiary)
            }
            if app.wakeState == .failed { failedActions }
            // .verifying'de de iptal olabilsin: sağlık OK ama bağlanamıyorsa (ör. token hatası)
            // pencere ~90sn kilitlenmesin.
            if app.wakeState == .waking || app.wakeState == .verifying { cancelButton }
        }
    }

    private var icon: some View {
        Group {
            switch app.wakeState {
            case .connected:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            default:
                Image(systemName: "power").foregroundStyle(Color.accentColor)
                    .scaleEffect(pulse ? 1.12 : 0.94)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }
        }
        .font(.system(size: 40))
    }

    private var title: String {
        switch app.wakeState {
        case .waking:     return "PC uyandırılıyor"
        case .verifying:  return "PC yanıt verdi"
        case .connected:  return "Bağlandı"
        case .failed:     return "Uyandırılamadı"
        case .idle:       return ""
        }
    }

    private var subtitle: String {
        switch app.wakeState {
        case .waking:     return "Uyandırma sinyalleri gönderiliyor (yerel WOL + ESP32). PC'nin açılması bekleniyor…"
        case .verifying:  return "PC ayağa kalktı, Shrimp'e bağlanılıyor…"
        case .connected:  return "Shrimp menüsüne dönülüyor…"
        case .failed:     return "PC 90 sn içinde yanıt vermedi. Aynı ağdaysan WOL'un açık olduğundan; uzaktaysan ESP32 aracının açık ve aynı ağda olduğundan emin ol."
        case .idle:       return ""
        }
    }

    private var failedActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { app.startWake() } label: {
                    Label("Tekrar dene", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Kapat") { app.cancelWake() }
                    .buttonStyle(.bordered)
            }
            if !app.wakeTopic.isEmpty {
                VStack(spacing: 2) {
                    Text("ESP32 ntfy konusu").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(app.wakeTopic).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                }
            }
        }
    }

    private var cancelButton: some View {
        Button("Vazgeç") { app.cancelWake() }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
    }
}

/// Gömülü Tailscale (tsnet) login gerektiğinde: tarayıcıda onay kartı.
struct TsnetLoginOverlay: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "network.badge.shield.half.filled").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                Text("Tailscale'e Giriş").font(.title3).bold()
                Text("Shrimp'in gömülü Tailscale'i PC'ne bağlanmak için hesabınla eşleşmeli. Tarayıcıda onayla; bu cihaz (shrimp-mac) tailnet'ine eklenir.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { app.openTsnetLogin() } label: {
                    Label("Tarayıcıda Giriş Yap", systemImage: "arrow.up.right.square")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("Onayladıktan sonra otomatik bağlanır.").font(.caption).foregroundStyle(.tertiary)
                Button("Vazgeç") { app.cancelTsnetLogin() }   // iptal → overlay kapanır, app kilitlenmez
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 380).padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
    }
}
