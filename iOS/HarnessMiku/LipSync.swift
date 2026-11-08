import Foundation

struct SpeechSegment: Sendable {
    let text: String
    let start: Double
    let end: Double
}

struct SpeechAudio: Sendable {
    let audio: Data
    let segments: [SpeechSegment]
}

struct LipPose: Equatable, Sendable {
    let open: Double
    let form: Double
    let pucker: Double
    static let closed = LipPose(open: 0, form: 0, pucker: 0)
}

enum LipVowel: Sendable {
    case closed, a, e, i, o, u

    // The model's existing mouth rig supplies five articulations without changing artwork.
    var pose: LipPose {
        switch self {
        case .closed: return .closed
        case .a: return LipPose(open: 0.85, form: 0, pucker: 0)
        case .e: return LipPose(open: 0.48, form: 0.45, pucker: 0.45)
        case .i: return LipPose(open: 0.16, form: 0.8, pucker: 0.65)
        case .o: return LipPose(open: 0.6, form: 0, pucker: -0.75)
        case .u: return LipPose(open: 0.28, form: 0, pucker: -0.95)
        }
    }

    static func phoneme(_ text: String) -> LipVowel {
        // Apple voices may deliver IPA or a written Hangul vowel. Consonants close the mouth.
        for scalar in text.lowercased().unicodeScalars {
            if let vowel = korean(scalar.value)?.last { return vowel }
            switch scalar {
            case "a", "ɑ", "ɐ", "ʌ", "ə": return .a
            case "e", "ɛ", "æ", "œ", "ø": return .e
            case "i", "ɪ", "ɨ", "ɯ": return .i
            case "o", "ɔ": return .o
            case "u", "ʊ", "y", "ʉ": return .u
            default: continue
            }
        }
        return .closed
    }

    static func korean(_ code: UInt32) -> [LipVowel]? {
        let index: Int
        switch code {
        case 0xAC00...0xD7A3: index = Int((code - 0xAC00) / 28 % 21)
        case 0x1161...0x1175: index = Int(code - 0x1161)
        case 0x314F...0x3163: index = Int(code - 0x314F)
        default: return nil
        }
        // Compound vowels keep their rounded or palatal lead-in before the final vowel.
        let vowels: [[LipVowel]] = [
            [.a], [.e], [.i, .a], [.i, .e], [.a], [.e], [.i, .a], [.i, .e],
            [.o], [.o, .a], [.o, .e], [.o, .e], [.i, .o], [.u], [.u, .a],
            [.u, .e], [.u, .i], [.i, .u], [.i], [.i], [.i]
        ]
        return vowels[index]
    }
}

struct LipTimeline: Sendable {
    struct Cue: Sendable {
        let start: Double
        let end: Double
        let vowel: LipVowel
    }
    let cues: [Cue]

    init(segments: [SpeechSegment]) {
        var built: [Cue] = []
        var previousEnd = 0.0
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            guard segment.start.isFinite, segment.end.isFinite, segment.end > segment.start else { continue }
            let start = max(0, previousEnd, segment.start)
            guard segment.end > start else { continue }
            let parts = Self.parts(segment.text)
            let total = parts.reduce(0) { $0 + $1.weight }
            guard total > 0 else { continue }
            var cursor = start
            for part in parts {
                let end = min(segment.end, cursor + (segment.end - start) * part.weight / total)
                built.append(Cue(start: cursor, end: end, vowel: part.vowel))
                cursor = end
            }
            previousEnd = segment.end
        }
        cues = built
    }

    func pose(at time: Double) -> LipPose {
        guard time.isFinite else { return .closed }
        // Binary search avoids scanning every cue during long spoken answers.
        var lower = 0, upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].end <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower < cues.count, cues[lower].start <= time else { return .closed }
        return cues[lower].vowel.pose
    }

    static func estimatedDuration(_ text: String, rate: Float) -> Double {
        let weight = parts(text).reduce(0) { $0 + $1.weight }
        return max(0.08, weight * 0.18 * 0.5 / max(0.1, Double(rate)))
    }

    private struct Part {
        let vowel: LipVowel
        let weight: Double
    }

    private static func parts(_ text: String) -> [Part] {
        // NFC makes decomposed Hangul follow the same articulation as ordinary syllables.
        var text = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "</?(soft|emphasis|slow|whisper)>", with: "", options: .regularExpression)
        // The fallback uses Korean cardinal readings when the provider gives written digits.
        let numbers = try! NSRegularExpression(pattern: "[0-9]+")
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .spellOut
        for match in numbers.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let number = Int64(text[range]),
                  let spoken = formatter.string(from: NSNumber(value: number)) else { continue }
            text.replaceSubrange(range, with: spoken)
        }
        var result: [Part] = []
        for scalar in text.unicodeScalars {
            let code = scalar.value
            if let vowels = LipVowel.korean(code) {
                let syllable = (0xAC00...0xD7A3).contains(code)
                let onset = syllable ? (code - 0xAC00) / 588 : 11
                let coda = syllable ? (code - 0xAC00) % 28 : 0
                let closedOnset = [6, 7, 8, 17].contains(onset) // ㅁ, ㅂ, ㅃ, ㅍ
                if closedOnset { result.append(Part(vowel: .closed, weight: 0.18)) }
                for vowel in vowels {
                    result.append(Part(vowel: vowel, weight: 0.82 / Double(vowels.count)))
                }
                if [16, 17, 18, 26].contains(coda) { result.append(Part(vowel: .closed, weight: 0.18)) }
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                result.append(Part(vowel: .closed, weight: 0.2))
            } else if CharacterSet.punctuationCharacters.contains(scalar) {
                result.append(Part(vowel: .closed, weight: 0.8))
            } else if CharacterSet.letters.contains(scalar) {
                result.append(Part(vowel: LipVowel.phoneme(String(scalar)), weight: 0.55))
            }
        }
        return result
    }
}
