// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MikuBonsaiMLX",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MikuBonsaiMLX", targets: ["MikuBonsaiMLX"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "c8dabc63e7018d0b1567b2171f8df5dd8a334a55"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.33.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0")
    ],
    targets: [
        .target(name: "MikuBonsaiMLX", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ])
    ],
    swiftLanguageModes: [.v5]
)
