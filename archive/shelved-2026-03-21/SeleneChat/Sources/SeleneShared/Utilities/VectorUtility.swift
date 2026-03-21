import Foundation

/// Compute cosine similarity between two vectors. Returns -1.0 to 1.0.
/// Returns 0.0 for empty, mismatched, or zero-magnitude vectors.
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0.0 }

    var dotProduct: Float = 0.0
    var magnitudeA: Float = 0.0
    var magnitudeB: Float = 0.0

    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        magnitudeA += a[i] * a[i]
        magnitudeB += b[i] * b[i]
    }

    let magnitude = sqrtf(magnitudeA) * sqrtf(magnitudeB)
    guard magnitude > 0 else { return 0.0 }

    return dotProduct / magnitude
}

/// Serialize [Float] to raw bytes for SQLite BLOB storage.
/// Format: contiguous Float32 values in native byte order.
public func serializeEmbedding(_ embedding: [Float]) -> Data {
    return embedding.withUnsafeBufferPointer { buffer in
        Data(buffer: buffer)
    }
}

/// Deserialize raw bytes from SQLite BLOB to [Float].
/// Returns nil if data size is not a multiple of Float size.
public func deserializeEmbedding(_ data: Data) -> [Float]? {
    let floatSize = MemoryLayout<Float>.size
    guard data.count % floatSize == 0 else { return nil }

    let count = data.count / floatSize
    return data.withUnsafeBytes { rawBuffer in
        let floatBuffer = rawBuffer.bindMemory(to: Float.self)
        return Array(floatBuffer.prefix(count))
    }
}
