import CryptoKit
import Foundation
import OnnxRuntimeBindings
import ZIPFoundation

actor LocalMikuRVC {
    static let shared = LocalMikuRVC()
    static let outputSampleRate = 40000
    private static let directory = URL.applicationSupportDirectory.appending(path: "HatsuneMikuRVC-1", directoryHint: .isDirectory)
    private static let files = [
        "miku.onnx": (110200895, "224ac677dc8bb43dd066a2231c92415e829f402b729de44be845c0b2e4cf38e3"),
        "contentvec.onnx": (378550151, "4b31ed3d95a568fab7952de923ff7f7d3d17128ea6fce69f665509d24c3156db")
    ]
    static var isInstalled: Bool {
        files.allSatisfy { name, expected in
            let url = directory.appending(path: name)
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == expected.0
        }
    }
    private var sessions: (ORTEnv, ORTSession, ORTSession)?

    func install(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let base = Self.directory.deletingLastPathComponent()
        var temp = base.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let archive = try Archive(url: url, accessMode: .read)
        for (name, (size, digest)) in Self.files {
            guard let entry = archive[name], entry.type == .file, entry.uncompressedSize == UInt64(size) else {
                throw MikuError("Hatsune Miku RVC 음성 ZIP을 선택해 줘.")
            }
            let file = temp.appending(path: name)
            guard fm.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            var hash = SHA256(), count = 0
            _ = try archive.extract(entry) { block in
                try Task.checkCancellation()
                count += block.count
                guard count <= size else { throw MikuError("음성 모델의 크기가 일치하지 않아.") }
                hash.update(data: block)
                try handle.write(contentsOf: block)
            }
            guard count == size, hash.finalize().map({String(format:"%02x", $0)}).joined() == digest else {
                throw MikuError("음성 모델이 원본과 일치하지 않아.")
            }
        }
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try temp.setResourceValues(attributes)
        if fm.fileExists(atPath: Self.directory.path) {
            _ = try fm.replaceItemAt(Self.directory, withItemAt: temp)
        } else { try fm.moveItem(at: temp, to: Self.directory) }
        sessions = nil
    }

    private func models() throws -> (ORTEnv, ORTSession, ORTSession) {
        if let sessions { return sessions }
        guard Self.isInstalled else { throw MikuError("설정에서 미쿠 음성 ZIP을 먼저 가져와 줘.") }
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        let encoder = try ORTSession(env: env, modelPath: Self.directory.appending(path:"contentvec.onnx").path, sessionOptions: options)
        let voice = try ORTSession(env: env, modelPath: Self.directory.appending(path:"miku.onnx").path, sessionOptions: options)
        let result = (env, encoder, voice)
        sessions = result
        return result
    }

    private func tensor<T>(_ samples: [T], _ type: ORTTensorElementDataType, _ shape: [Int]) throws -> ORTValue {
        let bytes = samples.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress, length: $0.count) }
        return try ORTValue(tensorData: bytes, elementType: type, shape: shape.map { NSNumber(value:$0) })
    }

    private func floats(_ value: ORTValue?) throws -> [Float] {
        guard let value else { throw MikuError("음성 모델 출력이 비어 있어.") }
        let bytes = try value.tensorData()
        guard bytes.length.isMultiple(of: MemoryLayout<Float>.stride) else { throw MikuError("음성 모델 출력 크기 오류") }
        return Array(UnsafeBufferPointer(start: bytes.bytes.assumingMemoryBound(to: Float.self), count: bytes.length / 4))
    }

    // Estimate voiced F0 at 10 ms intervals using a normalized difference
    // function. The unvoiced value is 0 Hz; RVC reserves coarse bin 1 for it.
    private func pitch(_ samples: [Float], frames: Int) throws -> ([Float], [Int64]) {
        var hz = [Float](repeating: 0, count: frames), bins = [Int64](repeating: 1, count: frames)
        let minMel = 1127 * log(1.0 + 50.0 / 700), maxMel = 1127 * log(1.0 + 1100.0 / 700)
        for f in 0..<frames {
            try Task.checkCancellation()
            let start = f * 160 - 240
            var x = [Float](repeating: 0, count: 320)
            for i in x.indices {
                let k = start + i * 2
                if k >= 0 && k + 1 < samples.count { x[i] = (samples[k] + samples[k+1]) * 0.5 }
            }
            guard x.reduce(Float.zero, { $0 + $1 * $1 }) / Float(x.count) > 0.000015 else { continue }
            var scores = [Float](repeating: 1, count: 121), total: Float = 0
            for lag in 1...120 {
                var d: Float = 0
                for i in 0..<200 { let v = x[i] - x[i+lag]; d += v * v }
                total += d
                if total > 0 { scores[lag] = d * Float(lag) / total }
            }
            guard var lag = (8..<120).first(where: { scores[$0] < 0.18 }) else { continue }
            while lag < 119 && scores[lag+1] < scores[lag] { lag += 1 }
            hz[f] = 8000 / Float(lag)
            let mel = 1127 * log(1 + Double(hz[f]) / 700)
            bins[f] = Int64(max(1, min(255, ((mel-minMel)*254/(maxMel-minMel)+1).rounded())))
        }
        return (hz, bins)
    }

    func convert(_ input: [Float]) throws -> [Float] {
        guard !input.isEmpty else { throw MikuError("낭독할 소리가 비어 있어.") }
        let (_, encoder, voice) = try models()
        // A bounded window keeps transformer attention memory independent of reply length.
        let context = 1600, hop = 32000
        var output = [Float]()
        for offset in stride(from: 0, to: input.count, by: hop) {
            try Task.checkCancellation()
            let end = min(offset+hop,input.count), count = end-offset
            let length = ((count + 2*context + 319)/320)*320 + 400
            var window = [Float](repeating: 0, count: length)
            for i in window.indices {
                let k = offset-context+i
                if input.indices.contains(k) { window[i] = input[k] }
            }
            let encoded = try encoder.run(withInputs: ["audio": try tensor(window,.float,[1,length])],
                                          outputNames: ["unit12"], runOptions: nil)
            let units = try floats(encoded["unit12"])
            guard units.count.isMultiple(of: 768) && !units.isEmpty else { throw MikuError("음성 특징 크기 오류") }
            let frames = units.count / 768 * 2
            var phone = [Float](); phone.reserveCapacity(units.count * 2)
            for i in stride(from: 0, to: units.count, by: 768) {
                let row = units[i..<i+768]
                phone.append(contentsOf: row); phone.append(contentsOf: row)
            }
            let (hz, bins) = try pitch(window, frames: frames)
            let values = try voice.run(withInputs: [
                "phone": try tensor(phone,.float,[1,frames,768]),
                "phone_lengths": try tensor([Int64(frames)],.int64,[1]),
                "pitch": try tensor(bins,.int64,[1,frames]),
                "nsff0": try tensor(hz,.float,[1,frames]),
                "sid": try tensor([Int64(0)],.int64,[1])
            ], outputNames: ["audio"], runOptions: nil)
            let audio = try floats(values["audio"]), first = context * 5/2, last = first + count*5/2
            guard last <= audio.count else { throw MikuError("음성 변환 길이가 일치하지 않아.") }
            output.append(contentsOf: audio[first..<last])
        }
        return output
    }
}
