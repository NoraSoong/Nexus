import Foundation
import XCTest

@testable import NexusCore

final class NexusBackgroundWorkTests: XCTestCase {
    @MainActor
    func testOperationDoesNotRunOnMainThread() async throws {
        XCTAssertTrue(Thread.isMainThread)

        let ranOnMainThread = try await NexusBackgroundWork.run {
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }
}
