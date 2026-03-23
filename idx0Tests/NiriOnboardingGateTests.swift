import XCTest
@testable import idx0

final class NiriOnboardingGateTests: XCTestCase {
    func testAutoShowWhenNiriEnabledFirstRunSeenAndSessionActive() {
        var settings = AppSettings()
        settings.niriCanvasEnabled = true
        settings.hasSeenFirstRun = true
        settings.hasSeenNiriOnboarding = false

        let shouldShow = NiriOnboardingGate.shouldAutoShow(
            settings: settings,
            hasActiveSession: true,
            isAlreadyPresented: false
        )

        XCTAssertTrue(shouldShow)
    }

    func testDoesNotAutoShowBeforeFirstRunIsCompleted() {
        var settings = AppSettings()
        settings.niriCanvasEnabled = true
        settings.hasSeenFirstRun = false
        settings.hasSeenNiriOnboarding = false

        let shouldShow = NiriOnboardingGate.shouldAutoShow(
            settings: settings,
            hasActiveSession: true,
            isAlreadyPresented: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testDoesNotAutoShowAfterOnboardingAlreadySeen() {
        var settings = AppSettings()
        settings.niriCanvasEnabled = true
        settings.hasSeenFirstRun = true
        settings.hasSeenNiriOnboarding = true

        let shouldShow = NiriOnboardingGate.shouldAutoShow(
            settings: settings,
            hasActiveSession: true,
            isAlreadyPresented: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testDoesNotAutoShowWithoutActiveSession() {
        var settings = AppSettings()
        settings.niriCanvasEnabled = true
        settings.hasSeenFirstRun = true
        settings.hasSeenNiriOnboarding = false

        let shouldShow = NiriOnboardingGate.shouldAutoShow(
            settings: settings,
            hasActiveSession: false,
            isAlreadyPresented: false
        )

        XCTAssertFalse(shouldShow)
    }
}
