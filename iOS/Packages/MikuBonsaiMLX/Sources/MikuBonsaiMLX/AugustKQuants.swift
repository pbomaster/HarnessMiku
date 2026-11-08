import MLX

/// Indexing matches ggml's dequantize_row_q4_K / dequantize_row_q6_K.
/// A simdgroup evaluates one output neuron during decode, directly from the packed rows.
enum AugustKQuants {
    static let header = """
        inline float augHalf(device const uchar* p) {
            return float(as_type<half>(ushort(uint(p[0]) | (uint(p[1]) << 8))));
        }
        inline float augQ4(device const uchar* p, uint i) {
            uint group = i / 32;
            device const uchar* sc = p + 4;
            uint scale, minimum;
            if (group < 4) {
                scale = sc[group] & 63; minimum = sc[group+4] & 63;
            } else {
                scale = (sc[group+4] & 15) | ((sc[group-4] >> 6) << 4);
                minimum = (sc[group+4] >> 4) | ((sc[group] >> 6) << 4);
            }
            uint q = p[16 + (i / 64) * 32 + i % 32];
            q = (q >> ((group % 2) * 4)) & 15;
            return augHalf(p) * float(scale * q) - augHalf(p+2) * float(minimum);
        }
        inline float augQ6(device const uchar* p, uint i) {
            uint halfIndex = i / 128, quarter = (i % 128) / 32, lane = i % 32;
            uint lo = p[halfIndex * 64 + (quarter % 2)*32 + lane];
            uint hi = p[128 + halfIndex * 32 + lane];
            int q = int(((lo >> (4 * (quarter/2))) & 15) | (((hi >> (2*quarter)) & 3) << 4)) - 32;
            return augHalf(p+208) * float(as_type<char>(p[192 + i / 16])) * float(q);
        }
        """
    struct Kernels {
        let dot: MLXFast.MLXFastKernel
        let unpack: MLXFast.MLXFastKernel
        let embed: MLXFast.MLXFastKernel
        init(_ bits: Int) {
            let size = bits == 4 ? 144 : 210
            let weight = "augQ\(bits)(row + (col / 256) * \(size), col % 256)"
            dot = MLXFast.metalKernel(name: "augDotQ\(bits)", inputNames: ["w","x"], outputNames: ["out"], source: """
                uint gid = thread_position_in_grid.x, r = gid / 32, lane = gid % 32;
                device const uchar* row = w + r * w_shape[1];
                float sum = 0;
                for (uint col = lane; col < uint(x_shape[1]); col += 32) {
                    sum += \(weight) * float(x[col]);
                }
                float total = simd_sum(sum);
                if (!lane) out[r] = half(total);
                """, header: AugustKQuants.header)
            unpack = MLXFast.metalKernel(name: "augUnpackQ\(bits)", inputNames: ["w"], outputNames: ["out"], source: """
                uint col = thread_position_in_grid.x, r = thread_position_in_grid.y;
                device const uchar* row = w + r * w_shape[1];
                uint width = uint(w_shape[1]) / \(size) * 256;
                out[r*width+col] = half(\(weight));
                """, header: AugustKQuants.header)
            embed = MLXFast.metalKernel(name: "augEmbedQ\(bits)", inputNames: ["w","ids"], outputNames: ["out"], source: """
                uint col = thread_position_in_grid.x, t = thread_position_in_grid.y;
                device const uchar* row = w + ids[t] * w_shape[1];
                uint width = uint(w_shape[1]) / \(size) * 256;
                out[t*width+col] = half(\(weight));
                """, header: AugustKQuants.header)
        }
    }
    static let four = Kernels(4), six = Kernels(6)
    static func linear(_ x: MLXArray, _ w: AugustGGUF.Tensor) -> MLXArray {
        let kernels = w.type == 12 ? four : six
        if x.dim(0) == 1 {
            return kernels.dot([w.array, x], grid: (w.rows * 32,1,1), threadGroup: (256,1,1),
                               outputShapes: [[1,w.rows]], outputDTypes: [.float16])[0]
        }
        // Only expand the current projection; MLX can then use its tiled dense prefill kernels.
        let dense = kernels.unpack([w.array], grid: (w.width,w.rows,1), threadGroup: (256,1,1),
                                   outputShapes: [[w.rows,w.width]], outputDTypes: [.float16])[0]
        return matmul(x, dense.T)
    }
    static func embedding(_ tokens: [Int32], _ w: AugustGGUF.Tensor) -> MLXArray {
        let kernels = w.type == 12 ? four : six
        return kernels.embed([w.array, MLXArray(tokens)], grid: (w.width,tokens.count,1), threadGroup: (256,1,1),
                             outputShapes: [[tokens.count,w.width]], outputDTypes: [.float16])[0]
    }
}
