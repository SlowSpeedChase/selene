import XCTest
import SeleneShared

final class NoteEssenceTests: XCTestCase {
    func testNoteHasEssenceProperty() {
        let note = Note.mock(
            essence: "Core insight about morning routines",
            fidelityTier: "summary"
        )
        XCTAssertEqual(note.essence, "Core insight about morning routines")
        XCTAssertEqual(note.fidelityTier, "summary")
    }

    func testNoteEssenceDefaultsToNil() {
        let note = Note.mock()
        XCTAssertNil(note.essence)
        XCTAssertNil(note.fidelityTier)
    }

    func testAllFidelityTierValues() {
        for tier in ["full", "high", "summary", "skeleton"] {
            let note = Note.mock(fidelityTier: tier)
            XCTAssertEqual(note.fidelityTier, tier)
        }
    }
}
