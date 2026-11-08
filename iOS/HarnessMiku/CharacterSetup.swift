import SwiftUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

enum CharacterFiles {
    static let root = URL.applicationSupportDirectory.appending(path: "Live2D-v1", directoryHint: .isDirectory)
    static var ready: Bool { FileManager.default.fileExists(atPath: root.appending(path: ".complete").path) }

    static func install(_ source: URL) throws {
        if ready { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let error = MikuError("지원하는 제작자 원본 ZIP을 선택해 줘. 파일이 손상되었으면 다시 받아 줘.")
        guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 512 * 1024 * 1024 else { throw error }
        let archive = try Archive(url: source, accessMode: .read)
        let manifestURL = Bundle.main.bundleURL.appending(path: "Stage/model-hashes.json")
        let hashes = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: manifestURL))
        let fm = FileManager.default
        let staging = root.deletingLastPathComponent().appending(path: UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var seen = Set<String>()
        let prefix = "RetrynowMiku/VTS Model File/"
        for entry in archive {
            guard entry.path.hasPrefix(prefix) else { continue }
            let name = String(entry.path.dropFirst(prefix.count))
            guard let digest = hashes[name] else { continue }
            guard seen.insert(name).inserted, entry.type == .file, entry.uncompressedSize <= 16 * 1024 * 1024 else { throw error }
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                guard data.count + chunk.count <= 16 * 1024 * 1024 else { throw error }
                data.append(chunk)
            }
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest else { throw error }
            let dest = staging.appending(path: name)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if name.hasPrefix("RetrynowMiku.4096/") {
                guard let image = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumb = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1024
                      ] as CFDictionary),
                      let output = CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil)
                else { throw error }
                CGImageDestinationAddImage(output, thumb, nil)
                guard CGImageDestinationFinalize(output) else { throw error }
            } else { try data.write(to: dest) }
        }
        guard seen == Set(hashes.keys), !seen.isEmpty else { throw error }
        try Data().write(to: staging.appending(path: ".complete"))
        var folder = staging
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        do { try fm.moveItem(at: staging, to: root) }
        catch { if !ready { throw error } }
    }
}

struct CharacterSetup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var ready = CharacterFiles.ready
    @State private var picking = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        if ready { content() }
        else {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.rectangle").font(.largeTitle).accessibilityHidden(true)
                Text("미쿠 불러오기").font(.title.bold())
                Text("파일 앱에서 제작자의 원본 New1007-RetrynowMiku.zip을 선택해 주세요. 한 번 가져오면 다음부터 바로 열려요.")
                    .multilineTextAlignment(.center)
                if loading { ProgressView("캐릭터 확인 중…") }
                else { Button("모델 ZIP 선택") { picking = true }.buttonStyle(.borderedProminent) }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .padding().frame(maxWidth: 420)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
                do {
                    let url = try result.get()
                    loading = true
                    message = nil
                    Task {
                        do { try await Task.detached { try CharacterFiles.install(url) }.value; ready = true }
                        catch { message = error.localizedDescription }
                        loading = false
                    }
                } catch { if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription } }
            }
        }
    }
}
