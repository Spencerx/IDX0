import SwiftUI

// MARK: - Sheets Modifier

struct MainWindowSheets: ViewModifier {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { !sessionService.settings.hasSeenFirstRun },
                    set: { showing in
                        if !showing {
                            sessionService.saveSettings { $0.hasSeenFirstRun = true }
                        }
                    }
                )
            ) {
                FirstRunSheet()
                    .environmentObject(coordinator)
                    .environmentObject(sessionService)
                    .environmentObject(workflowService)
            }
            .sheet(isPresented: $coordinator.showingNewSessionSheet) {
                NewSessionSheet(preset: coordinator.newSessionPreset)
                    .environmentObject(coordinator)
                    .environmentObject(sessionService)
                    .environmentObject(workflowService)
                    .frame(width: 480)
            }
            .sheet(isPresented: $coordinator.showingRenameSessionSheet) {
                RenameSessionSheet()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $coordinator.showingKeyboardShortcuts) {
                KeyboardShortcutsSheet()
                    .environmentObject(sessionService)
            }
            .sheet(
                isPresented: Binding(
                    get: { coordinator.showingNiriOnboarding },
                    set: { showing in
                        coordinator.showingNiriOnboarding = showing
                        if !showing {
                            sessionService.saveSettings { settings in
                                settings.hasSeenNiriOnboarding = true
                            }
                        }
                    }
                )
            ) {
                NiriOnboardingSheet()
                    .environmentObject(coordinator)
                    .environmentObject(sessionService)
            }
            .sheet(item: $workflowService.activeHandoffComposer) { draft in
                HandoffComposerSheet(initialDraft: draft)
                    .environmentObject(sessionService)
                    .environmentObject(workflowService)
                    .frame(width: 560)
            }
            .sheet(item: $sessionService.pendingWorktreeInspector) { request in
                WorktreeInspectorSheet(repoPath: request.repoPath)
                    .environmentObject(sessionService)
                    .frame(width: 680, height: 460)
            }
    }
}

