import XCTest
@testable import idx0

final class PaneNodeTests: XCTestCase {
    func testTerminalProperties() {
        let firstController = UUID()
        let secondController = UUID()
        let tree = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .terminal(id: UUID(), controllerID: firstController),
            second: .terminal(id: UUID(), controllerID: secondController),
            fraction: 0.4
        )

        XCTAssertEqual(tree.terminalControllerIDs, [firstController, secondController])
        XCTAssertEqual(tree.terminalCount, 2)
    }

    func testSplittingMatchingTerminalCreatesSplit() {
        let terminalID = UUID()
        let existingController = UUID()
        let newController = UUID()
        let root = PaneNode.terminal(id: terminalID, controllerID: existingController)

        let split = root.splitting(
            controllerID: existingController,
            direction: .vertical,
            newControllerID: newController
        )

        guard case .split(_, let direction, let first, let second, let fraction) = split else {
            XCTFail("Expected split node")
            return
        }

        XCTAssertEqual(direction, .vertical)
        XCTAssertEqual(fraction, 0.5)
        XCTAssertEqual(first.terminalControllerIDs, [existingController])
        XCTAssertEqual(second.terminalControllerIDs, [newController])
        XCTAssertEqual(split.terminalCount, 2)
    }

    func testSplittingNonMatchingTerminalReturnsUnchangedTree() {
        let root = PaneNode.terminal(id: UUID(), controllerID: UUID())
        let unchanged = root.splitting(controllerID: UUID(), direction: .horizontal, newControllerID: UUID())
        XCTAssertEqual(unchanged, root)
    }

    func testRemovingControllerCollapsesSplit() {
        let firstController = UUID()
        let secondController = UUID()
        let tree = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .terminal(id: UUID(), controllerID: firstController),
            second: .terminal(id: UUID(), controllerID: secondController),
            fraction: 0.7
        )

        let collapsed = tree.removing(controllerID: firstController)
        guard case .terminal(_, let remainingController)? = collapsed else {
            XCTFail("Expected collapsed terminal")
            return
        }
        XCTAssertEqual(remainingController, secondController)
    }

    func testRemovingLastTerminalReturnsNil() {
        let controller = UUID()
        let tree = PaneNode.terminal(id: UUID(), controllerID: controller)

        XCTAssertNil(tree.removing(controllerID: controller))
    }
}
