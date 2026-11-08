import Foundation
import MLX
import MLXNN
import MLXLLM

// The official Bonsai packs store affine 2-bit weights in a rotated basis.
// Mirror the published prism_hadamard_qwen35 activation and embedding transforms.
struct InvalidPack: LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
}

private struct PackConfiguration: Decodable {
    struct Entry: Decodable {
        let path: String
        let block: Int
        let embedding: Bool
        let dtype: String
    }
    struct Quantization: Decodable { let bits: Int; let group_size: Int; let mode: String }
    private struct TextLimits: Decodable { let max_position_embeddings: Int }
    let maxContext: Int
    enum CodingKeys: String, CodingKey { case model_type, schema_version, text_config, modules, quantization }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model_type = try values.decode(String.self, forKey: .model_type)
        schema_version = try values.decode(Int.self, forKey: .schema_version)
        text_config = try values.decode(Qwen35TextConfiguration.self, forKey: .text_config)
        maxContext = try values.decode(TextLimits.self, forKey: .text_config).max_position_embeddings
        modules = try values.decode([Entry].self, forKey: .modules)
        quantization = try values.decode(Quantization.self, forKey: .quantization)
    }
    let model_type: String
    let schema_version: Int
    let text_config: Qwen35TextConfiguration
    let modules: [Entry]
    let quantization: Quantization
}

func rotate(_ input: MLXArray, block: Int, signs: MLXArray?, inverse: Bool = false) -> MLXArray {
    guard let signs else { return input }
    var x = input.asType(.float32)
    if !inverse { x = x * signs }
    x = hadamardTransform(x.reshaped(-1, block), scale: 1 / sqrt(Float(block))).reshaped(input.shape)
    if inverse { x = x * signs }
    return x.asType(input.dtype)
}

private final class RotatedLinear: Linear {
    let scales: MLXArray
    let biases: MLXArray
    let signs: MLXArray?
    let block: Int

    init(_ weight: MLXArray, _ scales: MLXArray, _ biases: MLXArray, _ signs: MLXArray?, _ block: Int) {
        self.scales = scales
        self.biases = biases
        self.signs = signs
        self.block = block
        super.init(weight: weight)
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        quantizedMatmul(rotate(x, block: block, signs: signs), weight, scales: scales, biases: biases,
                        groupSize: 128, bits: 2)
    }
}

private final class RotatedEmbedding: Embedding {
    let scales: MLXArray
    let biases: MLXArray
    let signs: MLXArray?
    let block: Int

    init(_ weight: MLXArray, _ scales: MLXArray, _ biases: MLXArray, _ signs: MLXArray?, _ block: Int) {
        self.scales = scales
        self.biases = biases
        self.signs = signs
        self.block = block
        super.init(weight: weight)
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let indices = x.reshaped(-1)
        let rows = dequantized(weight[indices], scales: scales[indices], biases: biases[indices],
                               groupSize: 128, bits: 2)
        let embedded = rows.reshaped(x.shape + [-1]).asType(.float16)
        return rotate(embedded, block: block, signs: signs, inverse: true)
    }

    override func asLinear(_ x: MLXArray) -> MLXArray {
        quantizedMatmul(rotate(x, block: block, signs: signs), weight, scales: scales, biases: biases,
                        groupSize: 128, bits: 2)
    }
}

func loadBonsai(at directory: URL) throws -> (Qwen35TextModel, Int) {
    let config = try JSONDecoder().decode(PackConfiguration.self,
        from: Data(contentsOf: directory.appendingPathComponent("config.json")))
    let q = config.quantization
    guard [1, 2].contains(config.schema_version), config.model_type == "prism_hadamard_qwen35",
          q.bits == 2, q.group_size == 128, q.mode == "affine" else {
        throw InvalidPack("지원되지 않는 Bonsai MLX 가중치 형식이야.")
    }
    let model = Qwen35TextModel(config.text_config)
    // A 27B text pack alone occupies 7.67 GB. Page its vocabulary and largest FFN projection
    // on demand to leave working space for the recurrent state and the long attention cache.
    let streamLayers = model.kvHeads.count > 32
    let streamed = Set(config.modules.map(\.path).filter {
        streamLayers && ($0 == "lm_head" || $0 == "model.embed_tokens" || $0.hasSuffix(".mlp.down_proj"))
    })
    let pages = streamed.isEmpty ? nil : try StreamedVocabulary(directory: directory)
    var weights = [String: MLXArray]()
    for (name, tensor) in try MappedBonsaiWeights.read(directory.appendingPathComponent("model.safetensors"), skipping: streamed) {
        if name.hasPrefix("vision_tower.") { continue }
        let key = name.hasPrefix("language_model.") ? String(name.dropFirst("language_model.".count)) : name
        weights[key] = tensor
    }
    let original = Dictionary(uniqueKeysWithValues: model.namedModules())
    var replacements = [(String, Module)]()
    for entry in config.modules {
        if streamed.contains(entry.path), let pages {
            let layer = try pages.make(path: entry.path, block: entry.block, embedding: entry.embedding)
            replacements.append((entry.path, layer))
            continue
        }
        guard let module = original[entry.path], let dense = (module as? Linear)?.weight ?? (module as? Embedding)?.weight,
              let w = weights[entry.path + ".weight"], let scales = weights[entry.path + ".scales"],
              let biases = weights[entry.path + ".biases"] else { throw InvalidPack("Bonsai 가중치 누락: " + entry.path) }
        let (rows, width) = dense.shape2
        let signs = weights[entry.path + ".signs"]
        guard entry.dtype == "float16", w.dtype == .uint32, w.shape == [rows, width / 16],
              scales.shape == [rows, width / 128], biases.shape == scales.shape,
              entry.embedding == (module is Embedding),
              entry.block == 0 ? signs == nil : ([512, 1024, 2048, 4096].contains(entry.block) &&
              width.isMultiple(of: entry.block) && signs?.shape == [width]) else {
            throw InvalidPack("Bonsai 가중치 형태 오류: " + entry.path)
        }
        let replacement: Module
        if entry.embedding { replacement = RotatedEmbedding(w, scales, biases, signs, entry.block) }
        else { replacement = RotatedLinear(w, scales, biases, signs, entry.block) }
        replacements.append((entry.path, replacement))
    }
    try model.update(modules: ModuleChildren.unflattened(replacements), verify: [.noUnusedKeys])
    // The streamed modules own file ranges instead of trainable MLX arrays.
    let expected = Set(model.parameters().flattened().map(\.0).filter { key in
        guard let dot = key.lastIndex(of: ".") else { return true }
        return !streamed.contains(String(key[..<dot]))
    })
    guard expected == Set(weights.keys) else { throw InvalidPack("텍스트 모델의 가중치 목록이 일치하지 않아.") }
    try model.update(parameters: ModuleParameters.unflattened(weights), verify: [.noUnusedKeys, .shapeMismatch])
    guard config.maxContext > 0 else { throw InvalidPack("모델 문맥 정보를 읽을 수 없어.") }
    return (model, config.maxContext)
}
