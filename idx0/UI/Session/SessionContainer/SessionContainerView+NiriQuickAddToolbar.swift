import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SessionContainerView {
    func niriCanvasToolbar(sessionID: UUID, layout: NiriCanvasLayout) -> some View {
        let activeWorkspace = niriActiveWorkspaceIndex(layout: layout).map { $0 + 1 } ?? 1
        let activeColumn = niriActiveColumnIndex(
            layout: layout,
            workspaceIndex: niriActiveWorkspaceIndex(layout: layout) ?? 0
        ).map { $0 + 1 } ?? 1

        return HStack(spacing: 8) {
            Text("w\(activeWorkspace) · c\(activeColumn)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(tc.tertiaryText)

            if layout.isOverviewOpen {
                Text("Overview")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tc.accent.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tc.accent.opacity(0.1), in: Capsule())
            }

            if sessionService.settings.niri.snapEnabled {
                Text("Snap")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tc.tertiaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tc.surface1.opacity(0.8), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(tc.windowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    func niriCanvasQuickAddButton(sessionID: UUID) -> some View {
        Button {
            niriQuickAddMenuPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tc.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tc.surface1.opacity(0.95))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tc.divider.opacity(0.9), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        .help("Add Tile")
        .popover(
            isPresented: $niriQuickAddMenuPresented,
            attachmentAnchor: .point(.topLeading),
            arrowEdge: .top
        ) {
            niriQuickAddMenuContent(sessionID: sessionID)
        }
    }

    @ViewBuilder
    func niriQuickAddMenuContent(sessionID: UUID) -> some View {
        let installedTools = workflowService.vibeTools.filter(\.isInstalled)
        let visibleApps = NiriAppUIVisibility.quickAddApps(from: sessionService.registeredNiriApps)

        VStack(alignment: .leading, spacing: 2) {
            // Header
            Text("Add Tile")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tc.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            // Apps section
            ForEach(visibleApps, id: \.id) { app in
                Button {
                    niriQuickAddMenuPresented = false
                    _ = sessionService.niriAddAppRight(in: sessionID, appID: app.id)
                } label: {
                    niriQuickAddRow(
                        icon: app.icon,
                        iconImageName: app.iconImageName,
                        title: app.displayName,
                        subtitle: app.menuSubtitle
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                niriQuickAddMenuPresented = false
                _ = sessionService.niriAddBrowserRight(in: sessionID)
            } label: {
                niriQuickAddRow(
                    icon: "globe",
                    title: "Browser",
                    subtitle: "Open web view tile"
                )
            }
            .buttonStyle(.plain)

            // Divider
            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)

            // Agentic CLIs section
            Text("Agentic CLIs")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tc.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            if installedTools.isEmpty {
                Text("No installed CLIs found.")
                    .font(.system(size: 10))
                    .foregroundStyle(tc.tertiaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                ForEach(installedTools, id: \.id) { tool in
                    Button {
                        niriQuickAddMenuPresented = false
                        niriLaunchToolInNewTile(sessionID: sessionID, toolID: tool.id)
                    } label: {
                        niriQuickAddRow(
                            icon: niriToolIconName(for: tool.id),
                            title: tool.displayName,
                            subtitle: tool.executableName
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tc.sidebarBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tc.surface2.opacity(0.5), lineWidth: 1)
        }
        .padding(6)
    }

    @ViewBuilder
    func niriQuickAddRow(icon: String, iconImageName: String? = nil, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if let imageName = iconImageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(tc.secondaryText)
            .frame(width: 24, height: 24)
            .background(tc.surface1, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tc.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(tc.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    func niriLaunchToolInNewTile(sessionID: UUID, toolID: String) {
        guard sessionService.sessions.contains(where: { $0.id == sessionID }) else { return }
        _ = sessionService.niriAddTerminalRight(in: sessionID)
        do {
            try workflowService.launchTool(toolID, in: sessionID)
        } catch {
            sessionService.postStatusMessage(error.localizedDescription, for: sessionID)
        }
    }

    func niriToolIconName(for toolID: String) -> String {
        switch toolID {
        case "claude":
            return "text.bubble"
        case "codex":
            return "terminal"
        case "gemini-cli":
            return "sparkles"
        case "opencode":
            return "chevron.left.forwardslash.chevron.right"
        case "droid":
            return "cpu"
        default:
            return "terminal"
        }
    }

}
