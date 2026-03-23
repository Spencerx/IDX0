import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SessionContainerView {
    func niriWorkspaceView(
        session: Session,
        layout: NiriCanvasLayout,
        workspace: NiriWorkspace,
        workspaceIndex: Int,
        metrics: NiriCanvasMetrics
    ) -> some View {
        let anchorColumn = niriAnchorColumnIndex(
            layout: layout,
            workspaceIndex: workspaceIndex
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text("Workspace \(workspaceIndex + 1)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tc.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: metrics.headerHeight, alignment: .leading)

            if workspace.columns.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tc.surface0.opacity(0.45))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(tc.tertiaryText)
                            Text("Drop here or add a terminal")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tc.tertiaryText)
                        }
                    }
                    .frame(width: metrics.tileWidth, height: metrics.tileHeight * 0.55)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(workspace.columns.enumerated()), id: \.element.id) { columnIndex, column in
                        // Drop zone before this column (place as new column to its left)
                        if layout.isOverviewOpen, niriDraggedItemBySession[session.id] != nil {
                            niriInterColumnDropZone(
                                sessionID: session.id,
                                workspaceID: workspace.id,
                                insertionIndex: columnIndex,
                                height: niriColumnContentHeight(column: column, metrics: metrics, isOverview: true),
                                metrics: metrics
                            )
                        }

                        niriColumnView(
                            session: session,
                            layout: layout,
                            workspace: workspace,
                            workspaceIndex: workspaceIndex,
                            column: column,
                            columnIndex: columnIndex,
                            metrics: metrics
                        )
                        .zIndex(niriTileDrag?.columnID == column.id && column.items.contains(where: { $0.id == niriTileDrag?.itemID }) ? 100 : 0)

                        if columnIndex < workspace.columns.count - 1 {
                            if layout.isOverviewOpen {
                                niriColumnResizeHandle(
                                    sessionID: session.id,
                                    workspace: workspace,
                                    leftColumn: column,
                                    rightColumn: workspace.columns[columnIndex + 1],
                                    metrics: metrics
                                )
                            } else {
                                Spacer()
                                    .frame(width: 5)
                            }
                        }
                    }

                    // Trailing drop zone after the last column
                    if layout.isOverviewOpen, niriDraggedItemBySession[session.id] != nil {
                        niriInterColumnDropZone(
                            sessionID: session.id,
                            workspaceID: workspace.id,
                            insertionIndex: workspace.columns.count,
                            height: metrics.tileHeight,
                            metrics: metrics
                        )
                    }
                }
                .animation(.spring(duration: 0.55, bounce: 0.12), value: workspace.columns.map(\.id))
                .offset(
                    x: -niriLeadingOffset(
                        for: workspace,
                        anchorColumnIndex: anchorColumn,
                        metrics: metrics
                    ),
                    y: 0
                )
            }
        }
    }

    @ViewBuilder
    func niriColumnView(
        session: Session,
        layout: NiriCanvasLayout,
        workspace: NiriWorkspace,
        workspaceIndex: Int,
        column: NiriColumn,
        columnIndex: Int,
        metrics: NiriCanvasMetrics
    ) -> some View {
        let columnWidth = niriColumnWidth(column: column, metrics: metrics)

        switch column.displayMode {
        case .normal:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(column.items.enumerated()), id: \.element.id) { itemIndex, item in
                    let itemHeight = layout.isOverviewOpen
                        ? niriOverviewItemHeight(column: column, item: item, metrics: metrics)
                        : niriItemHeight(item: item, metrics: metrics)
                    niriCanvasItemView(
                        session: session,
                        layout: layout,
                        workspace: workspace,
                        workspaceIndex: workspaceIndex,
                        column: column,
                        columnIndex: columnIndex,
                        item: item,
                        metrics: metrics,
                        itemHeight: itemHeight
                    )

                    if itemIndex < column.items.count - 1 {
                        if layout.isOverviewOpen {
                            niriItemResizeHandle(
                                sessionID: session.id,
                                workspace: workspace,
                                column: column,
                                upperItem: item,
                                lowerItem: column.items[itemIndex + 1],
                                metrics: metrics
                            )
                        } else {
                            Spacer()
                                .frame(height: 5)
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.55, bounce: 0.12), value: column.items.map(\.id))
            .frame(width: columnWidth)
        case .tabbed:
            let focusedItemID = column.focusedItemID ?? column.items.first?.id
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(column.items) { item in
                        let isSelected = item.id == focusedItemID
                        Button {
                            sessionService.niriSelectItem(sessionID: session.id, itemID: item.id)
                        } label: {
                            Text(niriItemTitle(sessionID: session.id, item: item))
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected ? tc.surface1 : tc.surface0.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .foregroundStyle(isSelected ? tc.primaryText : tc.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(tc.surface0.opacity(0.75))

                if let focusedItem = column.items.first(where: { $0.id == focusedItemID }) {
                    niriCanvasItemView(
                        session: session,
                        layout: layout,
                        workspace: workspace,
                        workspaceIndex: workspaceIndex,
                        column: column,
                        columnIndex: columnIndex,
                        item: focusedItem,
                        metrics: metrics,
                        itemHeight: niriItemHeight(item: focusedItem, metrics: metrics)
                    )
                } else if let first = column.items.first {
                    niriCanvasItemView(
                        session: session,
                        layout: layout,
                        workspace: workspace,
                        workspaceIndex: workspaceIndex,
                        column: column,
                        columnIndex: columnIndex,
                        item: first,
                        metrics: metrics,
                        itemHeight: niriItemHeight(item: first, metrics: metrics)
                    )
                }
            }
            .frame(width: columnWidth)
            .background(tc.surface0.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tc.divider.opacity(0.8), lineWidth: 1)
            }
        }
    }
}
