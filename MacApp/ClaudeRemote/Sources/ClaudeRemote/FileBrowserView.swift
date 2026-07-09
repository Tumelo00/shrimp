import SwiftUI

/// PC dosya sistemi gezgini (salt-okunur). Yollar Windows biçimindedir (C:\...).
struct FileBrowserView: View {
    @EnvironmentObject var app: AppState

    @State private var path = "C:\\"
    @State private var listing: FileListing?
    @State private var error: String?
    @State private var preview: FileContent?
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            // Yol çubuğu
            HStack(spacing: 8) {
                Button {
                    goUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(parentPath(path) == nil)

                Text(path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(8)
            .background(.bar)
            Divider()

            if let error {
                Text(error).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listing {
                List(listing.entries) { entry in
                    HStack {
                        Image(systemName: entry.dir ? "folder.fill" : "doc")
                            .foregroundStyle(entry.dir ? Color.accentColor : .secondary)
                        Text(entry.name)
                        Spacer()
                        if !entry.dir {
                            Text(fmtBytes(entry.size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if entry.dir {
                            path = joinPath(path, entry.name)
                        } else {
                            openPreview(joinPath(path, entry.name))
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: path) { await load() }
        .sheet(isPresented: $showPreview) {
            FilePreviewSheet(file: preview)
        }
    }

    private func load() async {
        error = nil
        do {
            listing = try await app.api.get("/api/files", query: ["path": path], as: FileListing.self)
        } catch let e {
            listing = FileListing(path: path, truncated: false, entries: [])
            error = e.localizedDescription
        }
    }

    private func openPreview(_ filePath: String) {
        Task {
            preview = try? await app.api.get("/api/file", query: ["path": filePath], as: FileContent.self)
            showPreview = preview != nil
        }
    }

    private func goUp() {
        if let parent = parentPath(path) { path = parent }
    }
}

func joinPath(_ base: String, _ name: String) -> String {
    base.hasSuffix("\\") ? base + name : base + "\\" + name
}

func parentPath(_ p: String) -> String? {
    let trimmed = p.hasSuffix("\\") ? String(p.dropLast()) : p
    guard let idx = trimmed.lastIndex(of: "\\") else { return nil }
    let parent = String(trimmed[..<idx])
    if parent.count <= 2 { return parent.count == 2 ? parent + "\\" : nil } // "C:" → "C:\"
    return parent
}

struct FilePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: FileContent?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file?.path ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if file?.truncated == true {
                    Text("(kısaltıldı)").font(.caption).foregroundStyle(.orange)
                }
                Button("Kapat") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            if let file {
                if file.binary {
                    Text("İkili dosya (\(fmtBytes(file.size))) — önizleme yok")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(file.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
