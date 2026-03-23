import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService

    var body: some View {
        TabView {
            GeneralSettingsTab(sessionService: sessionService)
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsTab(sessionService: sessionService)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            SessionSettingsTab(sessionService: sessionService, workflowService: workflowService)
                .tabItem { Label("Sessions", systemImage: "terminal") }

            KeyboardSettingsTab(sessionService: sessionService)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }

            SafetySettingsTab(sessionService: sessionService)
                .tabItem { Label("Safety", systemImage: "shield") }

            AdvancedSettingsTab(sessionService: sessionService)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            workflowService.refreshVibeTools()
        }
    }
}

