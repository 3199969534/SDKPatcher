import SwiftUI
import UniformTypeIdentifiers

/// 用系统文档选择器，并且直接拷贝文件到 App 内，避免 iCloud / 权限导致"点不动"
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

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
        .sheet(isPresented: $picking) {
            DocumentPicker { url in start(url) }
        }
        // 从系统「分享」菜单 / 文件 App 的"打开方式"进来的 IPA
        .onOpenURL { url in
            if !busy { start(url) }
        }
    }

    private func start(_ url: URL) {
        busy = true
        result = nil
        log = "已选择: \(url.lastPathComponent)\n处理中，请稍候…"
        let sdk = self.sdk, all = self.patchAll
        Task.detached {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let (out, lines) = try IPAPatcher.run(ipa: url, sdk: sdk, patchAll: all)
                await MainActor.run {
                    result = out
                    log = lines.joined(separator: "\n")
                    busy = false
                }
            } catch {
                await MainActor.run {
                    log = "出错: \(error.localizedDescription)"
                    busy = false
                }
            }
        }
    }
}
