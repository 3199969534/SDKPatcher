import Foundation
import ZIPFoundation

enum PatchError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let s): return s }
    }
}

enum IPAPatcher {
    static func parse(_ s: String) -> UInt32 {
        let p = s.split(separator: ".").compactMap { UInt32($0) } + [0, 0, 0]
        return (p[0] << 16) | (p[1] << 8) | p[2]
    }

    static func fmt(_ v: UInt32) -> String {
        "\(v >> 16).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    static func load32(_ d: Data, _ off: Int) -> UInt32 {
        d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
    }

    static func store32(_ d: inout Data, _ off: Int, _ v: UInt32) {
        d.withUnsafeMutableBytes { $0.storeBytes(of: v, toByteOffset: off, as: UInt32.self) }
    }

    // MARK: Mach-O

    static func patchThin(_ d: inout Data, base: Int, target: UInt32,
                          name: String, log: inout [String]) -> Bool {
        guard base + 32 <= d.count else { return false }
        let magic = load32(d, base)
        guard magic == 0xFEEDFACF || magic == 0xFEEDFACE else { return false }
        let hdr = magic == 0xFEEDFACF ? 32 : 28
        let ncmds = Int(load32(d, base + 16))
        var p = base + hdr
        var changed = false
        for _ in 0..<ncmds {
            guard p + 8 <= d.count else { break }
            let cmd = load32(d, p)
            let size = Int(load32(d, p + 4))
            if cmd == 0x32, p + 24 <= d.count {            // LC_BUILD_VERSION
                let plat = load32(d, p + 8)
                let sdk = load32(d, p + 16)
                if plat == 2 && sdk < target {
                    store32(&d, p + 16, target)
                    log.append("\(name): LC_BUILD_VERSION sdk \(fmt(sdk)) -> \(fmt(target))")
                    changed = true
                }
            } else if cmd == 0x25, p + 16 <= d.count {     // LC_VERSION_MIN_IPHONEOS
                let sdk = load32(d, p + 12)
                if sdk < target {
                    store32(&d, p + 12, target)
                    log.append("\(name): LC_VERSION_MIN_IPHONEOS sdk \(fmt(sdk)) -> \(fmt(target))")
                    changed = true
                }
            }
            if size < 8 { break }
            p += size
        }
        return changed
    }

    static func patchMachO(_ d: inout Data, target: UInt32,
                           name: String, log: inout [String]) -> Bool {
        guard d.count > 32 else { return false }
        let head = UInt32(bigEndian: load32(d, 0))
        if head == 0xCAFEBABE || head == 0xCAFEBABF {
            let is64 = head == 0xCAFEBABF
            let n = Int(UInt32(bigEndian: load32(d, 4)))
            guard n <= 20 else { return false }
            let entry = is64 ? 32 : 20
            var changed = false
            for i in 0..<n {
                let b = 8 + i * entry
                guard b + entry <= d.count else { break }
                var off = 0
                if is64 {
                    let hi = Int(UInt32(bigEndian: load32(d, b + 8)))
                    let lo = Int(UInt32(bigEndian: load32(d, b + 12)))
                    off = (hi << 32) | lo
                } else {
                    off = Int(UInt32(bigEndian: load32(d, b + 8)))
                }
                if patchThin(&d, base: off, target: target, name: name, log: &log) { changed = true }
            }
            return changed
        }
        return patchThin(&d, base: 0, target: target, name: name, log: &log)
    }

    // MARK: IPA

    static func run(ipa: URL, sdk: String, patchAll: Bool) throws -> (URL, [String]) {
        let target = parse(sdk)
        let short = sdk.split(separator: ".").prefix(2).joined(separator: ".")
        var log: [String] = []

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let outURL = dir.appendingPathComponent(
            ipa.deletingPathExtension().lastPathComponent + "_sdk\(short).ipa")
        try fm.copyItem(at: ipa, to: outURL)

        let archive = try Archive(url: outURL, accessMode: .update)
        let entries = Array(archive)

        guard let plistEntry = entries.first(where: {
            let c = $0.path.split(separator: "/")
            return c.count == 3 && c[0] == "Payload" && c[1].hasSuffix(".app") && c[2] == "Info.plist"
        }) else { throw PatchError.invalid("找不到 Payload/xxx.app/Info.plist，这不是有效的 IPA") }

        func read(_ e: Entry) throws -> Data {
            var d = Data()
            _ = try archive.extract(e) { d.append($0) }
            return d
        }

        let appDir = String(plistEntry.path.dropLast("Info.plist".count))
        let plistData = try read(plistEntry)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: &format) as? [String: Any],
            let exe = plist["CFBundleExecutable"] as? String
        else { throw PatchError.invalid("无法解析 Info.plist") }

        let mainPath = appDir + exe
        log.append("应用: \(appDir)  主程序: \(exe)")

        // (path, data, permissions, compression)
        var patches: [(String, Data, UInt16, CompressionMethod)] = []

        // 主程序
        guard let mainEntry = archive[mainPath] else {
            throw PatchError.invalid("找不到主程序 \(mainPath)")
        }
        var mainData = try read(mainEntry)
        if patchMachO(&mainData, target: target, name: exe, log: &log) {
            patches.append((mainPath, mainData, 0o755, .none))
        }
        mainData = Data()

        // 可选：Frameworks / 插件
        if patchAll {
            for e in entries where e.type == .file && e.path.hasPrefix(appDir)
                && e.path != mainPath && e.uncompressedSize > 4096 {
                let ext = (e.path as NSString).pathExtension.lowercased()
                guard ext == "" || ext == "dylib" else { continue }
                var d = try read(e)
                let short = String(e.path.dropFirst(appDir.count))
                if patchMachO(&d, target: target, name: short, log: &log) {
                    patches.append((e.path, d, 0o755, .none))
                }
            }
        }

        // Info.plist
        let mm = short
        log.append("Info.plist: DTSDKName -> iphoneos\(mm), DTPlatformVersion -> \(mm)")
        plist["DTSDKName"] = "iphoneos\(mm)"
        plist["DTPlatformVersion"] = mm
        let newPlist = try PropertyListSerialization.data(
            fromPropertyList: plist, format: format, options: 0)
        patches.append((plistEntry.path, newPlist, 0o644, .deflate))

        // 写回
        for (path, data, perm, method) in patches {
            if let old = archive[path] { try archive.remove(old) }
            try archive.addEntry(with: path, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 permissions: perm, compressionMethod: method) { pos, size in
                data.subdata(in: Int(pos)..<(Int(pos) + size))
            }
        }
        log.append("完成")
        return (outURL, log)
    }
}
