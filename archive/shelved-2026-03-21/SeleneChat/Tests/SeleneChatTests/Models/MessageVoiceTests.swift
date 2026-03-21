import SeleneShared
import XCTest
@testable import SeleneChat

final class MessageVoiceTests: XCTestCase {

    func testVoiceOriginatedDefaultsFalse() {
        let message = Message(role: .user, content: "hello", llmTier: .onDevice)
        XCTAssertFalse(message.voiceOriginated)
    }

    func testVoiceOriginatedCanBeSetTrue() {
        let message = Message(role: .user, content: "hello", llmTier: .onDevice, voiceOriginated: true)
        XCTAssertTrue(message.voiceOriginated)
    }

    func testVoiceOriginatedRoundTripsCodable() throws {
        let original = Message(role: .user, content: "hello", llmTier: .onDevice, voiceOriginated: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertTrue(decoded.voiceOriginated)
    }

    func testVoiceOriginatedFalseRoundTripsCodable() throws {
        let original = Message(role: .user, content: "hello", llmTier: .onDevice, voiceOriginated: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertFalse(decoded.voiceOriginated)
    }

    func testOldMessagesWithoutVoiceFieldDecodeSafely() throws {
        // Simulate old JSON without voiceOriginated field
        let json = """
        {"id":"00000000-0000-0000-0000-000000000000","role":"user","content":"hello","timestamp":0,"llmTier":"On-Device (Apple Intelligence)"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertFalse(decoded.voiceOriginated)
    }
}
