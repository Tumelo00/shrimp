import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("PC Bağlantısı") {
                TextField("Tailscale IP", text: $app.host, prompt: Text("100.x.x.x"))
                TextField("Port", text: $app.portText)
                SecureField("Token", text: $app.token)
                Button("Yeniden Bağlan") { app.connect() }
            }
            Section {
                Text("Token, PC'de `%USERPROFILE%\\.claude-remote\\config.json` dosyasındadır. Agent ilk çalıştığında konsola da yazar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = app.lastError {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
