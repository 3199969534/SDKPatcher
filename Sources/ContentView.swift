import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sdk = "27.1.0"
    @State private var patchAll = false
    @State private var picking = false
    @State private var busy = false
    @State private var log = ""
    @State private var result: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("目标 SDK") {
                    TextField("例如 27.1.0", text: $sdk)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("同时修改 Frameworks / 插件", isOn: $patchAll)
                }
                Section {
                    Button(busy ? "处理中…" : "选择 IPA 并修改") { picking = true }
                        .disabled(busy)
                    if let result {
                        ShareLink(item: result) {
                            Label("导出修改后的 IPA", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if !log.isEmpty {
                    Section("日志") {
                        Text(log).font(.system(.footnote, design: .monospaced))
                    }
                }
            }
            .navigationTitle("SDK Patcher")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { r in
            guard case .success(let url) = r else { return }
            start(url)
        }
    }

    private func start(_ url: URL) {
        busy = true; result = nil; log = ""
        let sdk = self.sdk, all = self.patchAll
        Task.detached {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let (out, lines) = try IPAPatcher.run(ipa: url, sdk: sdk, patchAll: all)
                await MainActor.run { result = out; log = lines.joined(separator: "\n"); busy = false }
            } catch {
                await MainActor.run { log = "出错: \(error.localizedDescription)"; busy = false }
            }
        }
    }
}
