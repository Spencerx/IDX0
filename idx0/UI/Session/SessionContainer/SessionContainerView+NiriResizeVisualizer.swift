import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SessionContainerView {
    func niriShowWorkspaceOSD(_ text: String) {
        niriWorkspaceSwitchOSDTask?.cancel()
        niriWorkspaceSwitchOSD = text
        niriWorkspaceSwitchOSDTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            niriWorkspaceSwitchOSD = nil
        }
    }

    func niriActiveResizeVisualizer(
        sessionID: UUID,
        layout: NiriCanvasLayout
    ) -> NiriResizeVisualizerState? {
        guard layout.isOverviewOpen else { return nil }
        guard sessionService.settings.niri.resizeCameraVisualizerEnabled else { return nil }
        return niriResizeVisualizerBySession[sessionID]
    }

    func niriSetResizeVisualizer(
        sessionID: UUID,
        state: NiriResizeVisualizerState
    ) {
        guard sessionService.settings.niri.resizeCameraVisualizerEnabled else {
            niriClearResizeVisualizer(sessionID: sessionID)
            return
        }
        niriResizeVisualizerBySession[sessionID] = state
    }

    func niriClearResizeVisualizer(sessionID: UUID) {
        niriResizeVisualizerBySession.removeValue(forKey: sessionID)
    }

    func niriSetColumnResizeVisualizer(
        sessionID: UUID,
        workspaceID: UUID,
        leftColumnID: UUID,
        rightColumnID: UUID?
    ) {
        niriSetResizeVisualizer(
            sessionID: sessionID,
            state: NiriResizeVisualizerState(
                kind: .column,
                workspaceID: workspaceID,
                primaryColumnID: leftColumnID,
                secondaryColumnID: rightColumnID,
                primaryItemID: nil,
                secondaryItemID: nil
            )
        )
    }

    func niriSetItemResizeVisualizer(
        sessionID: UUID,
        workspaceID: UUID,
        columnID: UUID,
        primaryItemID: UUID,
        secondaryItemID: UUID?
    ) {
        niriSetResizeVisualizer(
            sessionID: sessionID,
            state: NiriResizeVisualizerState(
                kind: .item,
                workspaceID: workspaceID,
                primaryColumnID: columnID,
                secondaryColumnID: nil,
                primaryItemID: primaryItemID,
                secondaryItemID: secondaryItemID
            )
        )
    }

    func niriStartColumnEdgeResizeVisualizer(
        sessionID: UUID,
        workspaceID: UUID,
        columnID: UUID,
        edge: NiriEdgeAlignment
    ) {
        let layout = sessionService.niriLayout(for: sessionID)
        guard let workspace = layout.workspaces.first(where: { $0.id == workspaceID }),
              let columnIndex = workspace.columns.firstIndex(where: { $0.id == columnID })
        else {
            niriSetColumnResizeVisualizer(
                sessionID: sessionID,
                workspaceID: workspaceID,
                leftColumnID: columnID,
                rightColumnID: nil
            )
            return
        }

        let leftColumnID: UUID
        let rightColumnID: UUID?
        switch edge {
        case .leading:
            leftColumnID = columnIndex > 0 ? workspace.columns[columnIndex - 1].id : columnID
            rightColumnID = leftColumnID == columnID ? nil : columnID
        case .trailing:
            leftColumnID = columnID
            rightColumnID = columnIndex + 1 < workspace.columns.count
                ? workspace.columns[columnIndex + 1].id
                : nil
        }

        niriSetColumnResizeVisualizer(
            sessionID: sessionID,
            workspaceID: workspaceID,
            leftColumnID: leftColumnID,
            rightColumnID: rightColumnID
        )
    }

    func niriStartItemEdgeResizeVisualizer(
        sessionID: UUID,
        workspaceID: UUID,
        columnID: UUID,
        itemID: UUID,
        edge: NiriVerticalEdgeAlignment
    ) {
        let layout = sessionService.niriLayout(for: sessionID)
        guard let workspace = layout.workspaces.first(where: { $0.id == workspaceID }),
              let column = workspace.columns.first(where: { $0.id == columnID }),
              let itemIndex = column.items.firstIndex(where: { $0.id == itemID })
        else {
            niriSetItemResizeVisualizer(
                sessionID: sessionID,
                workspaceID: workspaceID,
                columnID: columnID,
                primaryItemID: itemID,
                secondaryItemID: nil
            )
            return
        }

        let neighborID: UUID?
        switch edge {
        case .top:
            neighborID = itemIndex > 0 ? column.items[itemIndex - 1].id : nil
        case .bottom:
            neighborID = itemIndex + 1 < column.items.count ? column.items[itemIndex + 1].id : nil
        }

        niriSetItemResizeVisualizer(
            sessionID: sessionID,
            workspaceID: workspaceID,
            columnID: columnID,
            primaryItemID: itemID,
            secondaryItemID: neighborID
        )
    }

    func niriResizePreviewColumnID(
        visualizer: NiriResizeVisualizerState,
        layout: NiriCanvasLayout
    ) -> UUID {
        if let activeColumnID = layout.camera.activeColumnID,
           activeColumnID == visualizer.primaryColumnID || activeColumnID == visualizer.secondaryColumnID {
            return activeColumnID
        }
        return visualizer.primaryColumnID
    }

    func niriResizePreviewItemID(
        visualizer: NiriResizeVisualizerState,
        layout: NiriCanvasLayout
    ) -> UUID? {
        if let focusedItemID = layout.camera.focusedItemID,
           focusedItemID == visualizer.primaryItemID || focusedItemID == visualizer.secondaryItemID {
            return focusedItemID
        }
        return visualizer.primaryItemID
    }

    func niriResizePreviewSize(
        visualizer: NiriResizeVisualizerState,
        layout: NiriCanvasLayout,
        metrics: NiriCanvasMetrics
    ) -> CGSize? {
        guard let workspace = layout.workspaces.first(where: { $0.id == visualizer.workspaceID }) else {
            return nil
        }

        switch visualizer.kind {
        case .column:
            let previewColumnID = niriResizePreviewColumnID(visualizer: visualizer, layout: layout)
            guard let column = workspace.columns.first(where: { $0.id == previewColumnID }) else { return nil }

            let previewItem = column.items.first(where: { $0.id == (column.focusedItemID ?? layout.camera.focusedItemID) })
                ?? column.items.first

            // Always use non-overview proportions so this matches the fixed viewport mode.
            let previewHeight = niriItemHeight(item: previewItem, metrics: metrics)
            return CGSize(
                width: niriColumnWidth(column: column, metrics: metrics),
                height: previewHeight
            )
        case .item:
            guard let column = workspace.columns.first(where: { $0.id == visualizer.primaryColumnID }) else { return nil }
            guard let previewItemID = niriResizePreviewItemID(visualizer: visualizer, layout: layout) else { return nil }
            guard let item = column.items.first(where: { $0.id == previewItemID }) else { return nil }

            // Always use non-overview proportions so this matches the fixed viewport mode.
            let previewHeight = niriItemHeight(item: item, metrics: metrics)
            return CGSize(
                width: niriColumnWidth(column: column, metrics: metrics),
                height: previewHeight
            )
        }
    }

    @ViewBuilder
    func niriResizeVisualizerHUD(
        state: NiriResizeVisualizerState,
        layout: NiriCanvasLayout,
        metrics: NiriCanvasMetrics
    ) -> some View {
        let viewportSize = CGSize(
            width: max(130, min(210, metrics.tileWidth * 0.27)),
            height: max(84, min(134, metrics.tileHeight * 0.22))
        )
        let previewSize = niriResizePreviewSize(
            visualizer: state,
            layout: layout,
            metrics: metrics
        ) ?? CGSize(width: metrics.tileWidth, height: metrics.tileHeight)
        let rawWidthRatio = previewSize.width / max(metrics.tileWidth, 1)
        let rawHeightRatio = previewSize.height / max(metrics.tileHeight, 1)
        // Keep the miniature tile constrained to the viewport frame,
        // but continue reporting true percentage values above 100%.
        let widthRatio = max(0.18, min(1.0, rawWidthRatio))
        let heightRatio = max(0.18, min(1.0, rawHeightRatio))
        let tilePreviewSize = CGSize(
            width: viewportSize.width * widthRatio,
            height: viewportSize.height * heightRatio
        )
        let widthPercent = Int((rawWidthRatio * 100).rounded())
        let heightPercent = Int((rawHeightRatio * 100).rounded())
        let exceedsViewport = rawWidthRatio > 1.0 || rawHeightRatio > 1.0

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tc.accent)
                Text(state.kind == .column ? "Viewport: Column Resize" : "Viewport: Tile Resize")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tc.primaryText)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        tc.secondaryText.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tc.windowBackground.opacity(0.35))
                    )

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((exceedsViewport ? Color.orange : tc.accent).opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke((exceedsViewport ? Color.orange : tc.accent).opacity(0.72), lineWidth: 1)
                    }
                    .frame(width: tilePreviewSize.width, height: tilePreviewSize.height)
            }
            .frame(width: viewportSize.width, height: viewportSize.height)

            Text("Static viewport outline with live tile size")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tc.tertiaryText)
            Text("W \(widthPercent)% · H \(heightPercent)%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(tc.secondaryText)
            if exceedsViewport {
                Text("Overflowing viewport")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(tc.accent.opacity(0.38), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        .allowsHitTesting(false)
    }

}
