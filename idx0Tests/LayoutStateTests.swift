import Foundation
import XCTest
@testable import idx0

final class LayoutStateTests: XCTestCase {
    func testLayoutStateRoundTripsFocusPinParkStackAndRailSurface() throws {
        let sessionA = UUID()
        let sessionB = UUID()
        let stack = SessionStack(
            title: "Main",
            sessionIDs: [sessionA, sessionB],
            visibleSessionID: sessionB
        )

        let original = LayoutState(
            focusedSessionID: sessionA,
            focusModeEnabled: true,
            parkedSessionIDs: [sessionB],
            pinnedSessionIDs: [sessionA],
            stacks: [stack],
            lastVisibleSupportingSurfaceBySession: [sessionA: .terminal],
            lastRailSurfaceBySession: [sessionA: .checkpoints, sessionB: .compare]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)

        XCTAssertEqual(decoded.focusedSessionID, sessionA)
        XCTAssertTrue(decoded.focusModeEnabled)
        XCTAssertEqual(decoded.parkedSessionIDs, [sessionB])
        XCTAssertEqual(decoded.pinnedSessionIDs, [sessionA])
        XCTAssertEqual(decoded.stacks.first?.visibleSessionID, sessionB)
        XCTAssertEqual(decoded.lastVisibleSupportingSurfaceBySession[sessionA], .terminal)
        XCTAssertEqual(decoded.lastRailSurfaceBySession[sessionA], .checkpoints)
        XCTAssertEqual(decoded.lastRailSurfaceBySession[sessionB], .compare)
    }
}
