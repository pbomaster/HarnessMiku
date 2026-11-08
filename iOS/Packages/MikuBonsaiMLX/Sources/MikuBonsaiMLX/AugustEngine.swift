import Foundation
import MLX
import MLXNN

/// One request's KV cache and original, unmodified August 8B packed weights.
public final class AugustEngine {
    private typealias Tensor = AugustGGUF.Tensor
    private struct Layer {
        let norm, ffnNorm, qNorm, kNorm, q, k, v, o, gate, up, down: Tensor
    }
    private let embedding, head, finalNorm: Tensor
    private let layers: [Layer]
    private var cache: [(MLXArray, MLXArray)?] = Array(repeating: nil, count: 36)
    private var position = 0

    public init(url: URL) throws {
        let weights = try AugustGGUF.load(url)
        func get(_ name: String, _ width: Int, _ rows: Int = 1) throws -> Tensor {
            guard let t = weights[name + ".weight"], t.width == width, t.rows == rows,
                  rows == 1 ? t.type == 0 : [12, 14].contains(t.type) else {
                throw AugustModelError.invalid("예상한 가중치와 달라. " + name)
            }
            return t
        }
        embedding = try get("token_embd", 4096, 151936)
        head = try get("output", 4096, 151936)
        finalNorm = try get("output_norm", 4096)
        layers = try (0..<36).map { i in
            let p = "blk.\(i)."
            return try Layer(norm: get(p+"attn_norm",4096), ffnNorm: get(p+"ffn_norm",4096),
                             qNorm: get(p+"attn_q_norm",128), kNorm: get(p+"attn_k_norm",128),
                             q: get(p+"attn_q",4096,4096), k: get(p+"attn_k",4096,1024),
                             v: get(p+"attn_v",4096,1024), o: get(p+"attn_output",4096,4096),
                             gate: get(p+"ffn_gate",4096,12288), up: get(p+"ffn_up",4096,12288),
                             down: get(p+"ffn_down",12288,4096))
        }
    }

    /// Give all new input tokens in order. Only the final prefill chunk needs output scores.
    public func forward(_ tokens: [Int32], scores: Bool = true) throws -> [Float] {
        guard !tokens.isEmpty, tokens.count <= 128, position + tokens.count <= 3072,
              tokens.allSatisfy({ $0 >= 0 && $0 < 151936 }) else { throw AugustModelError.invalid("문맥 길이를 확인해 줘.") }
        let n = tokens.count
        func norm(_ x: MLXArray, _ w: Tensor) -> MLXArray { MLXFast.rmsNorm(x, weight: w.array, eps: 1e-6) }
        func rot(_ x: MLXArray, heads: Int, scale: Tensor) -> MLXArray {
            let shaped = x.reshaped(1, n, heads, 128).transposed(0,2,1,3)
            return MLXFast.RoPE(norm(shaped, scale), dimensions: 128, traditional: false, base: 1_000_000,
                                scale: 1, offset: position)
        }
        let linear = AugustKQuants.linear
        var x = AugustKQuants.embedding(tokens, embedding)
        for (i, l) in layers.enumerated() {
            try Task.checkCancellation()
            let a = norm(x, l.norm)
            let q = rot(linear(a,l.q), heads: 32, scale: l.qNorm)
            var k = rot(linear(a,l.k), heads: 8, scale: l.kNorm)
            var v = linear(a,l.v).reshaped(1,n,8,128).transposed(0,2,1,3)
            if let prior = cache[i] {
                k = concatenated([prior.0, k], axis: 2)
                v = concatenated([prior.1, v], axis: 2)
            }
            cache[i] = (k,v)
            let attention = MLXFast.scaledDotProductAttention(queries: q, keys: k, values: v,
                                                               scale: 1 / sqrt(Float(128)), mask: n == 1 ? .none : .causal)
            x = x + linear(attention.transposed(0,2,1,3).reshaped(n,4096),l.o)
            let f = norm(x,l.ffnNorm)
            x = x + linear(silu(linear(f,l.gate)) * linear(f,l.up),l.down)
            // Prevent dense prefill projections across layers from overlapping in memory.
            if n > 1 { eval(x,k,v) }
        }
        position += n
        guard scores else { eval(x); return [] }
        let last = x[(n-1)..<n]
        return linear(norm(last,finalNorm),head).asType(.float32).asArray(Float.self)
    }
}
