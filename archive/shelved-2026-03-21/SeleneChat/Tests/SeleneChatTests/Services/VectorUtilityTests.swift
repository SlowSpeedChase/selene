import SeleneShared
import XCTest
@testable import SeleneChat

final class VectorUtilityTests: XCTestCase {

    // MARK: - Cosine Similarity

    func testIdenticalVectorsReturnOne() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let result = cosineSimilarity(a, a)
        XCTAssertEqual(result, 1.0, accuracy: 0.0001)
    }

    func testOppositeVectorsReturnNegativeOne() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [-1.0, 0.0, 0.0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, -1.0, accuracy: 0.0001)
    }

    func testOrthogonalVectorsReturnZero() {
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [0.0, 1.0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testMismatchedLengthsReturnZero() {
        let a: [Float] = [1.0, 2.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0)
    }

    func testEmptyVectorsReturnZero() {
        let result = cosineSimilarity([], [])
        XCTAssertEqual(result, 0.0)
    }

    func testZeroVectorReturnZero() {
        let a: [Float] = [0.0, 0.0, 0.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let result = cosineSimilarity(a, b)
        XCTAssertEqual(result, 0.0)
    }

    func testSimilarVectorsReturnHighScore() {
        let a: [Float] = [1.0, 2.0, 3.0]
        let b: [Float] = [1.1, 2.1, 3.1]
        let result = cosineSimilarity(a, b)
        XCTAssertGreaterThan(result, 0.99)
    }

    // MARK: - Serialization

    func testSerializeDeserializeRoundTrip() {
        let original: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let data = serializeEmbedding(original)
        let restored = deserializeEmbedding(data)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored!.count, original.count)
        for (a, b) in zip(original, restored!) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }

    func testSerializeEmpty() {
        let data = serializeEmbedding([])
        let restored = deserializeEmbedding(data)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored!.count, 0)
    }

    func testDeserializeInvalidDataReturnsNil() {
        let badData = Data([0xFF, 0xFE])
        let result = deserializeEmbedding(badData)
        XCTAssertNil(result)
    }

    func testSerialize768DimVector() {
        let vector = (0..<768).map { Float($0) / 768.0 }
        let data = serializeEmbedding(vector)
        let restored = deserializeEmbedding(data)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored!.count, 768)
    }
}
