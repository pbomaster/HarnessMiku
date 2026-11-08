import Foundation
#if canImport(llama) && canImport(MikuBonsaiMLX)
import llama
import MLX
import MikuBonsaiMLX

actor AugustMLXInference {
    static let shared = AugustMLXInference()

    /// Use August's own embedded vocabulary and original sampling policy. Only MLX
    /// evaluates the transformer. The vocabulary-only llama handle never builds a context.
    func generate(url: URL, lines: [Line], progress: @Sendable (String) -> Void) throws -> String {
        try Task.checkCancellation()
        llama_backend_init()
        var params = llama_model_default_params()
        params.vocab_only = true
        params.n_gpu_layers = 0
        guard let model = llama_model_load_from_file(url.path, params) else { throw MikuError("8B 모델의 어휘를 열 수 없어.") }
        defer { llama_model_free(model) }
        guard let vocab = llama_model_get_vocab(model) else { throw MikuError("8B 모델의 어휘를 찾을 수 없어.") }
        let capacity = 3072, limit = 320

        func tokens(_ text: String, special: Bool = true, available: Int = 3072) -> [Int32]? {
            guard available >= 0, text.utf8.count <= Int(Int32.max) else { return nil }
            if text.isEmpty { return [] }
            guard available > 0 else { return nil }
            var ids = [Int32](repeating: 0, count: min(available, text.utf8.count + 8))
            let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &ids, Int32(ids.count), false, special)
            return count >= 0 ? Array(ids.prefix(Int(count))) : nil
        }
        let persona = try LocalMiku.persona() + "\n\n" + ConversationFacts.clock()
        guard let sysStart = tokens("<|im_start|>system\n"), let content = tokens(persona, special: false),
              let end = tokens("<|im_end|>\n"), let userStart = tokens("<|im_start|>user\n"),
              let assistantStart = tokens("<|im_start|>assistant\n"),
              let replyStart = tokens("<|im_start|>assistant\n<think>\n\n</think>\n\n") else {
            throw MikuError("8B 모델의 대화 형식을 읽지 못했어.")
        }
        let system = sysStart + content + end
        let reserved = system.count + replyStart.count + limit
        var space = capacity - reserved
        var history: [(role: String, tokens: [Int32])] = []
        for line in lines.suffix(24).reversed() where line.role == "user" || line.role == "assistant" {
            try Task.checkCancellation()
            let header = line.role == "user" ? userStart : assistantStart
            let body = line.role == "assistant" ? Performance(line.content).body : line.content
            guard let ids = tokens(body, special: false, available: space - header.count - end.count) else {
                if history.isEmpty { throw MikuError("이 질문이 로컬 모델의 문맥 길이보다 길어. 조금 나누어 보내 줘.") }
                break
            }
            let turn = header + ids + end
            history.append((line.role, turn))
            space -= turn.count
        }
        let retained = BonsaiWindow.retainedTurnCount(history, reserved: reserved, capacity: capacity)
        guard retained > 0 else { throw MikuError("이 질문을 현재 문맥에 담을 수 없어.") }
        let prompt = system + history.prefix(retained).reversed().flatMap(\.tokens) + replyStart
        let priorCache = Memory.cacheLimit
        Memory.cacheLimit = 32 << 20
        defer { Memory.clearCache(); Memory.cacheLimit = priorCache }
        progress("8B 모델 여는 중")
        let engine = try AugustEngine(url: url)
        var scores: [Float] = []
        for first in stride(from: 0, to: prompt.count, by: 64) {
            let last = min(first + 64, prompt.count)
            progress("질문 읽는 중 · \(first)/\(prompt.count)토큰")
            scores = try engine.forward(Array(prompt[first..<last]), scores: last == prompt.count)
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw MikuError("응답 생성을 시작하지 못했어.")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.65))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        var bytes = Data()
        for i in 0..<limit {
            try Task.checkCancellation()
            progress("답변 생성 중 · \(i)토큰")
            var options = scores.enumerated().map { llama_token_data(id: Int32($0.offset), logit: $0.element, p: 0) }
            let token: Int32 = try options.withUnsafeMutableBufferPointer { buffer in
                var options = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, selected: -1, sorted: false)
                llama_sampler_apply(sampler, &options)
                guard options.selected >= 0, options.selected < options.size, let data = options.data else {
                    throw MikuError("8B 모델의 다음 답변을 고르지 못했어.")
                }
                return data[Int(options.selected)].id
            }
            llama_sampler_accept(sampler, token)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if n < 0 {
                piece = [CChar](repeating: 0, count: Int(-n))
                n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard n >= 0 else { throw MikuError("로컬 답변을 읽지 못했어.") }
            bytes.append(contentsOf: piece.prefix(Int(n)).map { UInt8(bitPattern: $0) })
            if i + 1 < limit { scores = try engine.forward([token]) }
        }
        let reply = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw MikuError("모델이 빈 답변을 반환했어. 다시 말해 줘.") }
        return reply
    }
}
#endif
