import Foundation
#if os(iOS)
import MikuBonsaiMLX
#endif
#if canImport(llama)
import llama
import Metal
import os
#endif

enum LocalMiku {
    enum Model: String {
        case august, bonsai, bonsai9MLX
        var title: String {
            switch self {
            case .august: return "Miku August 8B"
            case .bonsai: return "Bonsai 2 27B"
            case .bonsai9MLX: return "Bonsai 2 9B MLX"
            }
        }
    }
    static var fixed64K: Bool { UserDefaults.standard.string(forKey: "bonsaiContextMode") == "fixed64k" }
    static let modelKey = "localChatModel"
    static var model: Model { Model(rawValue: UserDefaults.standard.string(forKey: modelKey) ?? "") ?? .august }
    static let fileName = "Miku-August-8B-Memory-Q4_K_M"
    static var selected: Bool { UserDefaults.standard.string(forKey: "chatRoute") == "local" }

    static func persona(bonsai: Bool = false) throws -> String {
        let name = bonsai ? "bonsai-persona" : "august-persona"
        let url = Bundle.main.bundleURL.appendingPathComponent("Stage/\(name).txt")
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MikuError("미쿠의 대화 설정을 읽을 수 없어. 앱을 업데이트해 줘.") }
        return text
    }

    #if os(iOS)
    static func reply(_ lines: [Line], model: Model, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        if model == .august {
            guard let installed = try await AugustPack.shared.locate(allowDownload: false) else {
                throw MikuError("설정 → 로컬 AI에서 8B 모델 받기를 눌러 줘.")
            }
            return try await AugustMLXInference.shared.generate(url: installed, lines: lines, progress: progress)
        }
        let isNine = model == .bonsai9MLX
        guard isNine ? Bonsai9Pack.ready : Bonsai27MLXPack.ready else {
            throw MikuError("설정 → 로컬 AI에서 선택한 Bonsai MLX 모델을 받아 줘.")
        }
        let turns = lines.map { line in
            BonsaiTurn(role: line.role, content: line.role == "assistant" ? Performance(line.content).body : line.content)
        }
        return try await BonsaiEngine.shared.reply(directory: isNine ? Bonsai9Pack.directory : Bonsai27MLXPack.directory,
            system: try persona(bonsai: true) + "\n\n" + ConversationFacts.clock(), turns: turns,
            capacity: fixed64K ? 65_536 : 262_144, progress: progress)
    }
    #endif
}

// The original 27B has 16 full-attention layers with 1,024 K and V elements each.
// The remaining recurrent layers reserve a fixed state. All budgets here are bytes.
enum BonsaiWindow {
    enum Cache: Int, CaseIterable {
        case full, eightBit, fourBit, hostFourBit, cpuFourBit
        var bytesPerToken: Int {
            switch self {
            case .full: return 65_536
            case .eightBit: return 34_816
            case .fourBit, .hostFourBit, .cpuFourBit: return 18_432
            }
        }
    }
    struct Plan {
        let cache: Cache
        let capacity: Int
        var microBatch: UInt32? = nil
        static func preferred(_ left: Plan, _ right: Plan) -> Bool {
            if left.capacity != right.capacity { return left.capacity > right.capacity }
            return left.cache.rawValue < right.cache.rawValue
        }
    }

    // Input turns arrive newest first. Always retain a contiguous suffix of the saved chat
    // whose oldest surviving turn is a user turn, leaving system + reply space untouched.
    static func retainedTurnCount(_ newestFirst: [(role: String, tokens: [Int32])],
                                  reserved: Int, capacity: Int) -> Int {
        var remaining = capacity - reserved
        var count = 0
        for turn in newestFirst {
            guard turn.tokens.count <= remaining else { break }
            remaining -= turn.tokens.count
            count += 1
        }
        while count > 0 && newestFirst[count - 1].role == "assistant" { count -= 1 }
        return count
    }

    static let fixedCapacity = 65_536
    static func fixedPlans(metalAvailable: Int, processAvailable: Int) -> [Plan] {
        let eligible = plans(requested: fixedCapacity, modelLimit: fixedCapacity, metalAvailable: metalAvailable,
                             processAvailable: processAvailable).filter { $0.capacity == fixedCapacity }
        var candidates = eligible.filter { $0.cache == .fourBit }
        // Measured additional Metal over the mapped weights at ubatch 16, plus
        // 24 MiB for late allocations. This keeps KV on GPU when ubatch 64 is too large.
        if metalAvailable >= 1_652_506_624 + (24 << 20), processAvailable >= 1_800_000_000 {
            candidates.append(Plan(cache: .fourBit, capacity: fixedCapacity, microBatch: 16))
        }
        return candidates + eligible.filter { $0.cache == .hostFourBit }
    }

    static func attempts(_ plans: [Plan], minimum: Int) -> [Plan] {
        let floor = (minimum + 255) / 256 * 256
        return plans.filter { $0.capacity >= floor }.flatMap { plan -> [Plan] in
            // Try progressively smaller requests if the first estimate no longer fits.
            // Keep competing layouts in capacity order, retaining the newest complete turn.
            var sizes = Set([plan.capacity, floor])
            for part in [7, 6, 4, 2] {
                sizes.insert(max(floor, plan.capacity * part / 8 / 256 * 256))
            }
            return sizes.map { Plan(cache: plan.cache, capacity: $0) }
        }.sorted(by: Plan.preferred)
    }

    static func plans(requested: Int, modelLimit: Int, metalAvailable: Int, processAvailable: Int) -> [Plan] {
        // Budget after mapping the weights. Leave space for the recurrent state, the
        // fixed part of the compute graph, chat UI and small runtime allocations.
        let mib = 1 << 20
        let wanted = min(modelLimit / 256 * 256, ((requested + 255) / 256) * 256)
        return Cache.allCases.compactMap { cache in
            let maxTokens: Int
            if cache == .cpuFourBit {
                // All weights stay file-backed on CPU. Includes the peak CPU graph
                // and transient allocations observed during the 262,144-token probe.
                maxTokens = (processAvailable - 896 * mib) / cache.bytesPerToken
            } else if cache == .hostFourBit {
                // CPU holds Q4 KV and the recurrent state. Metal still needs scratch
                // proportional to context length, even with a four-token microbatch.
                let gpuTokens = (metalAvailable - 48 * mib) / 5_376
                let cpuTokens = (processAvailable - 384 * mib) / (cache.bytesPerToken + 512)
                maxTokens = min(gpuTokens, cpuTokens)
            } else {
                // Measured GPU cache begins at ~196 MB over mapped weights.
                // Leave additional room for transient decode allocations.
                let available = min(metalAvailable - 224 * mib, processAvailable - 288 * mib)
                maxTokens = available / (cache.bytesPerToken + 4096)
            }
            let capacity = min(wanted, maxTokens / 256 * 256)
            return capacity >= 512 ? Plan(cache: cache, capacity: capacity) : nil
        }.sorted(by: Plan.preferred)
    }
}

#if canImport(llama) && !os(iOS)
actor MikuInference {
    static let shared = MikuInference()
    private let availableMemory: @Sendable () -> (Int, Int)
    init(availableMemory: @escaping @Sendable () -> (Int, Int) = { MikuInference.platformMemory() }) {
        self.availableMemory = availableMemory
        llama_backend_init()
    }

    static func platformMemory() -> (Int, Int) {
        let gpu = MTLCreateSystemDefaultDevice()
        let metalAvailable = gpu.map { max(0, Int($0.recommendedMaxWorkingSetSize) - $0.currentAllocatedSize) } ?? 0
        #if os(iOS) && !targetEnvironment(simulator)
        let processAvailable = Int(os_proc_available_memory())
        #else
        let processAvailable = metalAvailable
        #endif
        return (metalAvailable, processAvailable)
    }

    private enum AllocationError: LocalizedError {
        case weights, context
        var errorDescription: String? {
            switch self {
            case .weights: return "로컬 모델을 열 수 없어. 다른 앱을 닫고 다시 시도해 줘."
            case .context: return "로컬 모델의 작업 메모리를 확보하지 못했어."
            }
        }
    }

    func generate(url: URL, lines: [Line], bonsai: Bool = false, limit: Int = 320, progress: @Sendable (String) -> Void = { _ in }) throws -> String {
        try Task.checkCancellation()
        let fixed64K = bonsai && LocalMiku.fixed64K
        var mp = llama_model_default_params()
        mp.load_mode = LLAMA_LOAD_MODE_MMAP
        mp.n_gpu_layers = fixed64K ? 99 : -1
        if bonsai {
            mp.use_extra_bufts = false
            mp.no_host = true
        }
        mp.progress_callback = { _, _ in !Task.isCancelled }
        var cpuWeights = false
        var activeModel = llama_model_load_from_file(url.path, mp)
        if bonsai && !fixed64K && activeModel == nil {
            try Task.checkCancellation()
            mp.n_gpu_layers = 0
            cpuWeights = true
            activeModel = llama_model_load_from_file(url.path, mp)
        }
        guard let initialModel = activeModel else { throw AllocationError.weights }
        defer { if let activeModel { llama_model_free(activeModel) } }
        try Task.checkCancellation()
        var cp = llama_context_default_params()
        cp.n_ctx = 3072
        cp.n_batch = 128
        cp.n_ubatch = 64
        cp.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        cp.n_threads_batch = cp.n_threads
        guard let vocab = llama_model_get_vocab(initialModel) else {
            throw MikuError("모델의 대화 형식을 읽을 수 없어.")
        }
        let trainedWindow = Int(llama_model_n_ctx_train(initialModel))
        if fixed64K && trainedWindow < BonsaiWindow.fixedCapacity { throw AllocationError.context }
        let maxWindow = fixed64K ? BonsaiWindow.fixedCapacity : (bonsai ? trainedWindow : Int(cp.n_ctx))
        func tokens(_ text: String, special: Bool, fitting available: Int) -> [llama_token]? {
            let bytes = text.utf8.count
            guard available >= 0, bytes <= Int(Int32.max) else { return nil }
            if bytes == 0 { return [] }
            guard available > 0 else { return nil }
            var result = [llama_token](repeating: 0, count: min(available, bytes + 8))
            let n = llama_tokenize(vocab, text, Int32(bytes), &result, Int32(result.count), false, special)
            guard n >= 0 else { return nil }
            return Array(result.prefix(Int(n)))
        }
        func fixed(_ text: String, special: Bool = true) throws -> [llama_token] {
            guard let result = tokens(text, special: special, fitting: maxWindow) else {
                throw MikuError("모델의 대화 설정을 토큰으로 바꾸지 못했어.")
            }
            return result
        }
        let persona = try LocalMiku.persona(bonsai: bonsai) + "\n\n" + ConversationFacts.clock()
        let end = try fixed("<|im_end|>\n")
        let system = try fixed("<|im_start|>system\n") + fixed(persona, special: false) + end
        let suffix = try fixed("<|im_start|>assistant\n<think>\n\n</think>\n\n")
        let userStart = try fixed("<|im_start|>user\n")
        let assistantStart = try fixed("<|im_start|>assistant\n")
        let reserved = system.count + suffix.count + limit
        // This hybrid model also stores recurrent state. Removing interior KV positions
        // would leave that state contaminated. Rebuild from the pinned system prompt
        // and complete retained turns; the saved transcript is never truncated.
        var budget = maxWindow - reserved
        var droppedEarlierTurns = false
        var history: [(role: String, tokens: [llama_token])] = []
        for line in lines.suffix(bonsai ? lines.count : 24).reversed() {
            try Task.checkCancellation()
            guard ["user", "assistant"].contains(line.role) else { continue }
            let body = line.role == "assistant" ? Performance(line.content).body : line.content
            let role = line.role
            let header = role == "user" ? userStart : assistantStart
            guard let content = tokens(body, special: false, fitting: budget - header.count - end.count) else {
                if history.isEmpty { throw MikuError("이 질문이 로컬 모델의 문맥 길이보다 길어. 조금 나누어 보내 줘.") }
                droppedEarlierTurns = true
                break
            }
            let turn = header + content + end
            history.append((role, turn))
            budget -= turn.count
        }
        let desired = maxWindow - budget
        func answer(in ctx: OpaquePointer) throws -> String {
            guard let vocab = llama_model_get_vocab(llama_get_model(ctx)) else { throw AllocationError.weights }
            let capacity = Int(llama_n_ctx_seq(ctx))
            let count = BonsaiWindow.retainedTurnCount(history, reserved: reserved, capacity: capacity)
            let kept = history.prefix(count)
            let trimmed = droppedEarlierTurns || count < history.count
            guard !kept.isEmpty else { throw MikuError("이 질문을 현재 문맥에 담을 수 없어.") }
            var prompt = system + kept.reversed().flatMap { $0.tokens } + suffix
            func decode(_ buffer: UnsafeMutablePointer<llama_token>, _ count: Int) throws {
                try Task.checkCancellation()
                #if os(iOS) && !targetEnvironment(simulator)
                if bonsai && os_proc_available_memory() < 32 << 20 { throw AllocationError.context }
                #endif
                let status = llama_decode(ctx, llama_batch_get_one(buffer, Int32(count)))
                if status == -2 || status == 1 { throw AllocationError.context }
                guard status == 0 else {
                    throw MikuError("기기에서 모델 계산을 마치지 못했어.")
                }
            }
            let contextStatus = bonsai ? " · 문맥 \(capacity)" + (trimmed ? " · 이전 기록 일부 생략" : "") : ""
            try prompt.withUnsafeMutableBufferPointer { batch in
                for i in stride(from: 0, to: batch.count, by: Int(cp.n_batch)) {
                    progress("질문 읽는 중 · \(i)/\(batch.count)토큰" + contextStatus)
                    try decode(batch.baseAddress! + i, min(Int(cp.n_batch), batch.count - i))
                }
            }
            let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
            defer { llama_sampler_free(sampler) }
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.65))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
            var bytes = Data()
            for index in 0..<limit {
                progress("답변 생성 중 · \(index)토큰")
                try Task.checkCancellation()
                var token = llama_sampler_sample(sampler, ctx, -1)
                if llama_vocab_is_eog(vocab, token) { break }
                var piece = [CChar](repeating: 0, count: 256)
                var n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
                if n < 0 {
                    piece = [CChar](repeating: 0, count: Int(-n))
                    n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
                }
                guard n >= 0 else { throw MikuError("로컬 답변을 읽지 못했어.") }
                bytes.append(contentsOf: piece.prefix(Int(n)).map { UInt8(bitPattern: $0) })
                try decode(&token, 1)
            }
            let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw MikuError("모델이 빈 답변을 반환했어. 다시 말해 줘.") }
            return text
        }
        if !bonsai {
            guard let ctx = llama_init_from_model(initialModel, cp) else { throw AllocationError.context }
            defer { llama_free(ctx) }
            return try answer(in: ctx)
        }
        let (metalAvailable, processAvailable) = availableMemory()
        let minimum = reserved + (history.first?.tokens.count ?? 0)
        let attempts: [BonsaiWindow.Plan]
        if fixed64K {
            attempts = BonsaiWindow.fixedPlans(metalAvailable: metalAvailable, processAvailable: processAvailable)
        } else {
            let plans = BonsaiWindow.plans(requested: desired, modelLimit: maxWindow,
                                           metalAvailable: metalAvailable, processAvailable: processAvailable)
                .filter { !cpuWeights || $0.cache == .cpuFourBit }
            attempts = BonsaiWindow.attempts(plans, minimum: minimum)
            guard !attempts.isEmpty else {
                throw MikuError("현재 메모리로는 이 질문과 답변 공간을 함께 담을 수 없어. 질문을 나누거나 메모리 여유가 생긴 뒤 다시 시도해 줘.")
            }
        }
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        func allocate(_ plan: BonsaiWindow.Plan) -> OpaquePointer? {
            let wantsCPU = plan.cache == .cpuFourBit
            if wantsCPU != cpuWeights || activeModel == nil {
                if let current = activeModel { llama_model_free(current) }
                activeModel = nil
                cpuWeights = wantsCPU
                mp.n_gpu_layers = wantsCPU ? 0 : -1
                progress(wantsCPU ? "긴 대화를 위해 CPU 메모리로 전환 중" : "Bonsai GPU 준비 중")
                activeModel = llama_model_load_from_file(url.path, mp)
            }
            guard let model = activeModel else { return nil }
            cp.offload_kqv = !wantsCPU && plan.cache != .hostFourBit
            cp.op_offload = !wantsCPU
            // The fixed host-KV profile has ample Metal workspace at this length.
            // For the model's largest automatic windows use the smaller measured workspace.
            cp.n_ubatch = plan.microBatch ?? (plan.cache == .hostFourBit && !fixed64K ? 4 : 64)
            cp.n_ctx = UInt32(plan.capacity)
            switch plan.cache {
            case .full: cp.type_k = GGML_TYPE_F16
            case .eightBit: cp.type_k = GGML_TYPE_Q8_0
            case .fourBit, .hostFourBit, .cpuFourBit: cp.type_k = GGML_TYPE_Q4_0
            }
            cp.type_v = cp.type_k
            return llama_init_from_model(model, cp)
        }
        for plan in attempts {
            try Task.checkCancellation()
            guard let ctx = allocate(plan) else { continue }
            do {
                defer { llama_free(ctx) }
                if fixed64K && Int(llama_n_ctx_seq(ctx)) != BonsaiWindow.fixedCapacity { continue }
                return try answer(in: ctx)
            } catch AllocationError.context {
                // Some backends commit buffers during decode. No partial answer has been published.
                continue
            }
        }
        if fixed64K {
            throw MikuError("GPU 레이어와 Q4 캐시로 65,536토큰 문맥을 확보하지 못했어. 메모리 여유가 생긴 뒤 다시 시도하거나 설정에서 자동 최대를 골라 줘.")
        }
        throw AllocationError.context
    }
}
#endif
