import SwiftUI

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var sessionService: SessionService

    var body: some View {
        Form {
            Section {
                Picker("App Mode", selection: enumBinding(\.appMode)) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                Text("Terminal: clean terminal experience. Hybrid: agent features appear when relevant. Vibe Studio: all features always visible.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable Niri Canvas Mode (Experimental)", isOn: binding(\.niriCanvasEnabled))
                    Text("Turns the session surface into a two-dimensional scrollable canvas with terminal and browser tiles.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if sessionService.settings.niriCanvasEnabled {
                Section("Niri Mode") {
                    Picker("Default Column Display", selection: niriDefaultColumnDisplayBinding()) {
                        ForEach(NiriColumnDisplayMode.allCases, id: \.self) { mode in
                            Text(mode == .normal ? "Normal" : "Tabbed").tag(mode)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enable Snap", isOn: niriSnapEnabledBinding())
                        Text("When enabled, high-velocity gestures snap to workspace/column targets.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Resize Camera Visualizer", isOn: niriResizeCameraVisualizerBinding())
                        Text("Highlights the tiles affected while resizing in overview mode.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Snap Velocity Threshold")
                            Spacer(minLength: 0)
                            Text("\(Int(sessionService.settings.niri.gestures.snapVelocityThresholdPxPerSec)) px/s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: niriSnapVelocityThresholdBinding(),
                            in: 300...2200,
                            step: 25
                        )
                        .disabled(!sessionService.settings.niri.snapEnabled)
                        Text("Below this speed, release ends in free-pan. Above it, gesture snaps.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Gesture Decision Threshold")
                            Spacer(minLength: 0)
                            Text("\(Int(sessionService.settings.niri.gestures.decisionThresholdPx)) px")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: niriDecisionThresholdBinding(),
                            in: 8...40,
                            step: 1
                        )
                        Text("Distance before locking horizontal vs vertical gesture direction.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Swipe History Window")
                            Spacer(minLength: 0)
                            Text("\(sessionService.settings.niri.gestures.swipeHistoryMs) ms")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: niriSwipeHistoryBinding(),
                            in: 80...260,
                            step: 5
                        )
                        Text("Window used for velocity/projection when snapping.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hot Corners")
                            .font(.callout.weight(.medium))
                        Toggle("Top Left", isOn: niriHotCornerBinding(.topLeft))
                        Toggle("Top Right", isOn: niriHotCornerBinding(.topRight))
                        Toggle("Bottom Left", isOn: niriHotCornerBinding(.bottomLeft))
                        Toggle("Bottom Right", isOn: niriHotCornerBinding(.bottomRight))
                        Text("Hover to toggle overview when Niri mode is active.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                settingRow(
                    toggle: binding(\.sidebarVisible),
                    label: "Show Sidebar",
                    description: "Display the session sidebar on the left"
                )

                settingRow(
                    toggle: binding(\.inboxVisible),
                    label: "Show Workflow Rail",
                    description: "Display the supervision queue, timeline, and checkpoints panel"
                )

                Picker("External Links", selection: enumBinding(\.externalLinkRouting)) {
                    ForEach(ExternalLinkRouting.allCases, id: \.self) { routing in
                        Text(routing.displayLabel).tag(routing)
                    }
                }
                Text("How to open URLs detected in terminal output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("Browser Split Default Side", selection: enumBinding(\.browserSplitDefaultSide)) {
                    ForEach(SplitSide.allCases, id: \.self) { side in
                        Text(side == .right ? "Right" : "Bottom").tag(side)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { sessionService.settings[keyPath: keyPath] },
            set: { value in sessionService.saveSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func enumBinding<Value: Hashable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { sessionService.settings[keyPath: keyPath] },
            set: { value in sessionService.saveSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func niriDefaultColumnDisplayBinding() -> Binding<NiriColumnDisplayMode> {
        Binding(
            get: { sessionService.settings.niri.defaultColumnDisplayMode },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.defaultColumnDisplayMode = value
                }
            }
        )
    }

    private func niriDecisionThresholdBinding() -> Binding<Double> {
        Binding(
            get: { sessionService.settings.niri.gestures.decisionThresholdPx },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.gestures.decisionThresholdPx = value
                }
            }
        )
    }

    private func niriSnapEnabledBinding() -> Binding<Bool> {
        Binding(
            get: { sessionService.settings.niri.snapEnabled },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.snapEnabled = value
                }
            }
        )
    }

    private func niriResizeCameraVisualizerBinding() -> Binding<Bool> {
        Binding(
            get: { sessionService.settings.niri.resizeCameraVisualizerEnabled },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.resizeCameraVisualizerEnabled = value
                }
            }
        )
    }

    private func niriSnapVelocityThresholdBinding() -> Binding<Double> {
        Binding(
            get: { sessionService.settings.niri.gestures.snapVelocityThresholdPxPerSec },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.gestures.snapVelocityThresholdPxPerSec = value
                }
            }
        )
    }

    private func niriSwipeHistoryBinding() -> Binding<Double> {
        Binding(
            get: { Double(sessionService.settings.niri.gestures.swipeHistoryMs) },
            set: { value in
                sessionService.saveSettings { settings in
                    settings.niri.gestures.swipeHistoryMs = Int(value.rounded())
                }
            }
        )
    }

    private func niriHotCornerBinding(_ corner: NiriHotCorner) -> Binding<Bool> {
        Binding(
            get: { sessionService.settings.niri.hotCorners.contains(corner) },
            set: { enabled in
                sessionService.saveSettings { settings in
                    if enabled {
                        if !settings.niri.hotCorners.contains(corner) {
                            settings.niri.hotCorners.append(corner)
                        }
                    } else {
                        settings.niri.hotCorners.removeAll { $0 == corner }
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func settingRow(toggle: Binding<Bool>, label: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: toggle)
            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

