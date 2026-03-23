import Foundation

struct NiriOnboardingGate {
    static func shouldAutoShow(settings: AppSettings, hasActiveSession: Bool, isAlreadyPresented: Bool) -> Bool {
        guard settings.niriCanvasEnabled else {
            return false
        }
        guard hasActiveSession else {
            return false
        }
        guard settings.hasSeenFirstRun else {
            return false
        }
        guard !settings.hasSeenNiriOnboarding else {
            return false
        }
        guard !isAlreadyPresented else {
            return false
        }
        return true
    }
}
