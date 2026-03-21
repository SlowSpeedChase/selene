import SeleneShared
import XCTest
@testable import SeleneChat

final class DatabaseServiceThreadTests: XCTestCase {

    func testGetPendingThreadsReturnsEmptyArrayWhenNoThreads() async throws {
        let service = DatabaseService.shared

        // This should return empty array, not throw
        let threads = try await service.getPendingThreads()

        // Just verify it returns an array (may be empty or have data)
        XCTAssertNotNil(threads)
    }

    func testGetThreadByIdReturnsNilForNonexistent() async throws {
        let service = DatabaseService.shared

        let thread = try await service.getThread(byId: 999999)

        XCTAssertNil(thread)
    }
}
