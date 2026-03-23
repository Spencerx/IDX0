import SwiftUI
import XCTest
@testable import idx0

@MainActor
final class NiriAppRegistryTests: XCTestCase {
    func testVisibleDescriptorsExcludeHiddenApps() {
        let registry = NiriAppRegistry()
        registry.register(contentsOf: [
            descriptor(id: "visible-a", title: "Visible A", visible: true),
            descriptor(id: "hidden-b", title: "Hidden B", visible: false),
            descriptor(id: "visible-c", title: "Visible C", visible: true)
        ])

        XCTAssertEqual(registry.orderedDescriptors.map(\.id), ["visible-a", "hidden-b", "visible-c"])
        XCTAssertEqual(registry.visibleDescriptors.map(\.id), ["visible-a", "visible-c"])
    }

    func testRegisterReplacesDescriptorForExistingIDWithoutChangingOrder() {
        let registry = NiriAppRegistry()
        registry.register(contentsOf: [
            descriptor(id: "a", title: "A", visible: true),
            descriptor(id: "b", title: "B", visible: true)
        ])

        registry.register(descriptor(id: "a", title: "A Updated", visible: true))

        XCTAssertEqual(registry.orderedDescriptors.map(\.id), ["a", "b"])
        XCTAssertEqual(registry.descriptor(for: "a")?.displayName, "A Updated")
    }

    func testQuickAddVisibilityFiltersHiddenApps() {
        let visible = NiriAppUIVisibility.quickAddApps(from: appsForVisibilityFiltering())

        XCTAssertEqual(visible.map(\.id), ["visible-a", "visible-c"])
    }

    func testCommandPaletteVisibilityFiltersHiddenApps() {
        let visible = NiriAppUIVisibility.commandPaletteApps(from: appsForVisibilityFiltering())

        XCTAssertEqual(visible.map(\.id), ["visible-a", "visible-c"])
    }

    func testAppMenuVisibilityFiltersHiddenApps() {
        let visible = NiriAppUIVisibility.appMenuApps(from: appsForVisibilityFiltering())

        XCTAssertEqual(visible.map(\.id), ["visible-a", "visible-c"])
    }

    private func appsForVisibilityFiltering() -> [NiriAppDescriptor] {
        [
            descriptor(id: "visible-a", title: "Visible A", visible: true),
            descriptor(id: "hidden-b", title: "Hidden B", visible: false),
            descriptor(id: "visible-c", title: "Visible C", visible: true)
        ]
    }

    private func descriptor(id: String, title: String, visible: Bool) -> NiriAppDescriptor {
        NiriAppDescriptor(
            id: id,
            displayName: title,
            icon: "square.grid.2x2",
            menuSubtitle: "Subtitle",
            isVisibleInMenus: visible,
            supportsWebZoomPersistence: false,
            startTile: { _, _ in nil },
            retryTile: { _, _, _ in },
            stopTile: { _, _ in },
            ensureController: { _, _, _ in nil },
            makeTileView: { _, _, _ in AnyView(EmptyView()) },
            cleanupSessionArtifacts: nil
        )
    }
}
