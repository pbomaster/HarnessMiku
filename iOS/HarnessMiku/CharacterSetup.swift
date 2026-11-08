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
    // Bump when the Core protection terms presented here change.
    private static var termsVersion: String { "core-2.1-ko-1" }
    @AppStorage("cubismCoreAcceptedTerms") private var acceptedTerms = ""
    @State private var ready = CharacterFiles.ready
    @State private var picking = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        if acceptedTerms != Self.termsVersion {
            CubismCoreTerms { acceptedTerms = Self.termsVersion }
        } else if ready { content() }
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

private struct CubismCoreTerms: View {
    let accept: () -> Void
    @State private var declined = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Cubism Core 이용 조건")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                if declined {
                    Text("캐릭터 렌더러가 꺼져 있어요. 앱을 닫거나 이용 조건을 다시 확인할 수 있어요.")
                    Button("이용 조건 다시 보기") { declined = false }
                        .buttonStyle(.bordered)
                } else {
                    Text("Harness Miku는 캐릭터를 화면에 그릴 때 Live2D Cubism Core를 사용합니다. Core의 저작권은 Live2D Inc.에 있습니다.")
                    Text("Core는 이 앱에 포함된 형태로 이용할 수 있습니다. 법령이나 Live2D의 허락이 있는 경우를 제외하고, Core를 별도로 추출·복제·수정·재배포하거나 역설계·디컴파일·분해할 수 없습니다. 저작권 및 라이선스 표시를 유지해야 합니다.")
                    Text("아래 원문의 Core 보호 조항이 적용됩니다. 동의 여부는 이 기기에 저장됩니다.")
                    Link("Live2D 공식 이용 조건 읽기",
                         destination: URL(string: "https://www.live2d.com/eula/live2d-proprietary-software-license-agreement_en.html")!)
                    Button("동의하고 계속") { accept() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("cubism.accept")
                    Button("동의하지 않음") { declined = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("cubism.decline")
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
