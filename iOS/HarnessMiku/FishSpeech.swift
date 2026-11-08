import Foundation

// Never retry a partially generated stream. Only an explicit unsupported-route
// response allows Service to use the older synthesis endpoint once.
enum FishSpeech {
    enum EndpointError: LocalizedError {
        case unsupported(Int)
        var errorDescription: String? {
            switch self {
            case .unsupported(let status): return "Fish Audio \(status) · 이 음성 서버가 시간 정보가 있는 합성을 지원하지 않아."
            }
        }
    }

    static func synthesize(text: String, id: String, engine: String, key: String,
                           session: URLSession) async throws -> SpeechAudio {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.fish.audio/v1/tts/stream/with-timestamp")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(engine, forHTTPHeaderField: "model")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "reference_id": id.lowercased(), "format": "mp3", "latency": "balanced"
        ])
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw malformed() }
        guard (200..<300).contains(http.statusCode) else {
            try Task.checkCancellation()
            if [404, 405, 501].contains(http.statusCode) {
                throw EndpointError.unsupported(http.statusCode)
            }
            let hint: String
            switch http.statusCode {
            case 401, 403: hint = "설정에서 API 키와 접근 권한을 확인해 줘."
            case 402, 429: hint = "잔액이나 사용 한도를 확인해 줘."
            default: hint = "음성 ID와 합성 모델을 확인해 줘."
            }
            // Do not expose response bodies, which can echo credentials or spoken text.
            throw MikuError("Fish Audio \(http.statusCode) · \(hint)")
        }
        return try await collect(bytes, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, contentType: String) async throws -> SpeechAudio
    where Bytes.Element == UInt8 {
        let mime = contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let streaming = mime == "text/event-stream"
        guard streaming || mime.hasPrefix("audio/") || mime == "application/octet-stream" else { throw malformed() }
        var stream = Stream()
        var audio = Data()
        var count = 0
        try Task.checkCancellation()
        for try await byte in bytes {
            if count & 16_383 == 0 { try Task.checkCancellation() }
            count += 1
            if streaming { try stream.append(byte) }
            else {
                guard audio.count < maximumAudioBytes else { throw malformed() }
                audio.append(byte)
            }
        }
        try Task.checkCancellation()
        if streaming { return try stream.finish() }
        guard !audio.isEmpty else { throw malformed() }
        // A server may return ordinary audio without alignments. Reuse this audio;
        // the caller estimates its text timeline, without another synthesis charge.
        return SpeechAudio(audio: audio, segments: [])
    }

    private static let maximumAudioBytes = 32 << 20
    private static func malformed() -> MikuError { MikuError("Fish Audio 음성 응답을 읽을 수 없어. 다시 시도해 줘.") }

    struct Stream {
        private var line = Data()
        private var eventData = ""
        private var eventType = ""
        private var afterCR = false
        private var firstLine = true
        private var ended = false
        private var audio = Data()
        private var snapshots: [Int: [SpeechSegment]] = [:]
        private var observedChunks = Set<Int>()
        private var reliableAlignment = true
        private var events = 0

        mutating func append(_ byte: UInt8) throws {
            if byte == 10 && afterCR { afterCR = false; return }
            afterCR = byte == 13
            if byte == 10 || byte == 13 {
                guard var text = String(data: line, encoding: .utf8) else { throw FishSpeech.malformed() }
                line.removeAll(keepingCapacity: true)
                if firstLine { firstLine = false; if text.hasPrefix("\u{FEFF}") { text.removeFirst() } }
                try receive(text)
            } else {
                guard line.count < 16 << 20 else { throw FishSpeech.malformed() }
                line.append(byte)
            }
        }

        private mutating func receive(_ line: String) throws {
            if line.isEmpty { try dispatch(); return }
            if line.hasPrefix(":") { return }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(parts[0])
            var value = parts.count == 2 ? String(parts[1]) : ""
            if value.first == " " { value.removeFirst() }
            switch field {
            case "data":
                guard eventData.utf8.count + value.utf8.count < 16 << 20 else { throw FishSpeech.malformed() }
                if !eventData.isEmpty { eventData.append("\n") }
                eventData.append(value)
            case "event": eventType = value
            default: break // SSE id/retry fields do not change this one-shot request.
            }
        }

        private struct AudioChunk: Decodable { let audio_base64: String }
        private struct ChunkIdentity: Decodable { let chunk_seq: Int }
        private struct Metadata: Decodable {
            let chunk_seq: Int
            let chunk_audio_offset_sec: Double
            let alignment: Alignment
            struct Alignment: Decodable {
                let segments: [Segment]
                struct Segment: Decodable { let text: String; let start: Double; let end: Double }
            }
        }

        private mutating func dispatch() throws {
            defer { eventData = ""; eventType = "" }
            if eventType == "error" { throw FishSpeech.malformed() }
            guard !eventData.isEmpty else { return }
            if eventData == "[DONE]" { ended = true; return }
            guard !ended, events < 100_000 else { throw FishSpeech.malformed() }
            events += 1
            let data = Data(eventData.utf8)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["error"] == nil || object["error"] is NSNull,
                  let chunk = try? JSONDecoder().decode(AudioChunk.self, from: data),
                  let decoded = Data(base64Encoded: chunk.audio_base64),
                  audio.count + decoded.count <= FishSpeech.maximumAudioBytes else { throw FishSpeech.malformed() }
            audio.append(decoded) // Transport chunks append even when a timestamp repeats.
            // Track even null snapshots: otherwise a later unaligned content chunk
            // would leave the mouth closed after the last partially aligned word.
            guard let identity = try? JSONDecoder().decode(ChunkIdentity.self, from: data),
                  identity.chunk_seq >= 0, identity.chunk_seq <= 100_000 else {
                reliableAlignment = false; return
            }
            observedChunks.insert(identity.chunk_seq)
            guard let alignment = object["alignment"], !(alignment is NSNull) else { return }
            guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
                  metadata.chunk_seq >= 0, metadata.chunk_seq <= 100_000,
                  metadata.chunk_audio_offset_sec.isFinite, metadata.chunk_audio_offset_sec >= 0,
                  metadata.alignment.segments.count <= 100_000 else {
                reliableAlignment = false; return
            }
            let offset = metadata.chunk_audio_offset_sec
            var timeline: [SpeechSegment] = []
            for segment in metadata.alignment.segments {
                guard segment.start.isFinite, segment.end.isFinite,
                      segment.start >= 0, segment.end >= segment.start,
                      (offset + segment.end).isFinite else { reliableAlignment = false; return }
                timeline.append(SpeechSegment(text: segment.text, start: offset + segment.start, end: offset + segment.end))
            }
            // Each snapshot is cumulative, not another list of newly spoken words.
            snapshots[metadata.chunk_seq] = timeline
        }

        mutating func finish() throws -> SpeechAudio {
            try Task.checkCancellation()
            if !line.isEmpty {
                guard let text = String(data: line, encoding: .utf8) else { throw FishSpeech.malformed() }
                line.removeAll(); try receive(text)
            }
            try dispatch()
            guard !audio.isEmpty else { throw FishSpeech.malformed() }
            let completeAlignment = reliableAlignment && !observedChunks.isEmpty && observedChunks.allSatisfy {
                snapshots[$0]?.isEmpty == false
            }
            let segments = completeAlignment ? observedChunks.sorted().flatMap { snapshots[$0] ?? [] } : []
            return SpeechAudio(audio: audio, segments: segments)
        }
    }
}
