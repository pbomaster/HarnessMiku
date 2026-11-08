import Foundation
import Metal
import os
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

public struct BonsaiTurn: Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public actor BonsaiEngine {
    public static let shared = BonsaiEngine()

    public func reply(directory: URL, system: String, turns: [BonsaiTurn], capacity: Int, maxOutput: Int = 320,
                      greedy: Bool = false, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        guard turns.last?.role == "user", capacity > maxOutput, maxOutput > 0 else {
            throw InvalidPack("현재 대화와 문맥 길이를 확인해 줘.")
        }
        progress("MLX 모델 준비 중")
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        try Task.checkCancellation()
        let oldLimit = Memory.cacheLimit
        Memory.cacheLimit = min(oldLimit, 64 << 20)
        defer { Memory.clearCache(); Memory.cacheLimit = oldLimit }
        return try withError {
            let (model, modelLimit) = try loadBonsai(at: directory)
            // The large model releases weight pages after their matmuls. MLX graph tracing
            // cannot enclose those evaluations. Generation stays synchronous on this actor.
            let streaming = model.kvHeads.count > 32
            if streaming { MLX.compile(enable: false) }
            defer { if streaming { MLX.compile(enable: true) } }
            // Quantized full-attention layers grow per token. Recurrent layers hold fixed state.
            let device = MTLCreateSystemDefaultDevice()
            let available = device.map { max(0, Int($0.recommendedMaxWorkingSetSize) - $0.currentAllocatedSize) } ?? 0
            #if os(iOS) && !targetEnvironment(simulator)
            let headroom = min(available, Int(os_proc_available_memory()))
            #else
            let headroom = available
            #endif
            let fullLayers = model.kvHeads.count / 4
            let bytesPerToken = max(1, fullLayers * 2 * 1_024 * 36 / 64)
            let estimatedRoom = max(0, headroom - (256 << 20)) / bytesPerToken
            let window = min(capacity, modelLimit, capacity == 65_536 ? capacity : estimatedRoom)
            guard window > maxOutput else { throw InvalidPack("MLX가 대화를 시작할 메모리를 확보하지 못했어.") }
            func encode(_ text: String) -> [Int] { tokenizer.encode(text: text, addSpecialTokens: false) }
            // Escape literal control markers in dialogue before inserting the trusted role boundaries.
            func content(_ text: String) -> String { text.replacingOccurrences(of: "<|", with: "<\u{200B}|") }
            let prefix = encode("<|im_start|>system\n" + content(system) + "<|im_end|>\n")
            let suffix = encode("<|im_start|>assistant\n<think>\n\n</think>\n\n")
            var room = window - prefix.count - suffix.count - maxOutput
            var newestFirst: [(String, [Int])] = []
            for turn in turns.reversed() where turn.role == "user" || turn.role == "assistant" {
                try Task.checkCancellation()
                let ids = encode("<|im_start|>" + turn.role + "\n" + content(turn.content) + "<|im_end|>\n")
                guard ids.count <= room else { break }
                newestFirst.append((turn.role, ids))
                room -= ids.count
            }
            while newestFirst.last?.0 == "assistant" { newestFirst.removeLast() }
            guard !newestFirst.isEmpty else { throw InvalidPack("지금 질문이 모델의 문맥보다 길어. 나눠서 보내 줘.") }
            let ids = prefix + newestFirst.reversed().flatMap { $0.1 } + suffix
            #if os(iOS) && !targetEnvironment(simulator)
            guard ids.count + maxOutput <= estimatedRoom else {
                throw InvalidPack("현재 기기 메모리로 이 대화 길이를 처리하기 어려워. 자동 최대를 선택하거나 대화를 짧게 시작해 줘.")
            }
            #endif
            let trimmed = newestFirst.count < turns.count ? " · 이전 기록 일부 생략" : ""
            let settings = GenerateParameters(maxTokens: maxOutput, kvBits: 4, kvGroupSize: 64,
                temperature: greedy ? 0 : 0.7, topP: 0.8, topK: 20,
                presencePenalty: greedy ? nil : 1.5, presenceContextSize: 64,
                prefill: .init(stepSize: 64, progress: { read, total in
                    progress("질문 읽는 중 · \(read)/\(total)토큰" + trimmed)
                }))
            // KV storage grows with submitted tokens. Reserve the response in the logical window.
            let input = LMInput(tokens: MLXArray(ids.map(Int32.init)))
            // Start quantized before prefill, so reading a long history never creates a full FP16 cache first.
            let cache: [KVCache] = try model.newCache(parameters: settings).map { item in
                item is MambaCache ? item : QuantizedKVCache(groupSize: 64, bits: 4)
            }
            var stream = try TokenIterator(input: input, model: model, cache: cache, parameters: settings)
            var answer: [Int] = []
            let stop = Set(["<|im_end|>", "<|endoftext|>"].compactMap { tokenizer.convertTokenToId($0) })
            while answer.count < maxOutput {
                try Task.checkCancellation()
                #if os(iOS) && !targetEnvironment(simulator)
                guard os_proc_available_memory() > 64 << 20 else { throw InvalidPack("기기 메모리가 부족해 답변 생성을 멈췄어.") }
                #endif
                guard let id = stream.next(), !stop.contains(id) else { break }
                answer.append(id)
                progress("답변 생성 중 · \(answer.count)토큰")
            }
            let text = tokenizer.decode(tokens: answer, skipSpecialTokens: true).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw InvalidPack("모델이 빈 답을 냈어. 다시 말해 줘.") }
            return text
        }
    }
}
