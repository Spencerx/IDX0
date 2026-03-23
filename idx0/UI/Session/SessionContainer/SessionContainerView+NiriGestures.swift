import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SessionContainerView {
    @ViewBuilder
    func niriEdgeAutoScrollOverlay(sessionID: UUID, isOverviewOpen: Bool) -> some View {
        if niriDraggedItemBySession[sessionID] != nil {
            GeometryReader { proxy in
                let niriSettings = sessionService.settings.niri
                let horizontalTrigger = CGFloat(niriSettings.edgeViewScroll.triggerWidth)
                let verticalTrigger = CGFloat(niriSettings.edgeWorkspaceSwitch.triggerHeight)

                ZStack {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: horizontalTrigger)
                            .onHover { hovering in
                                niriHandleEdgeHover(
                                    sessionID: sessionID,
                                    direction: .left,
                                    hovering: hovering
                                )
                            }
                        Spacer(minLength: 0)
                        Color.clear
                            .frame(width: horizontalTrigger)
                            .onHover { hovering in
                                niriHandleEdgeHover(
                                    sessionID: sessionID,
                                    direction: .right,
                                    hovering: hovering
                                )
                            }
                    }

                    if isOverviewOpen {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: verticalTrigger)
                                .onHover { hovering in
                                    niriHandleEdgeHover(
                                        sessionID: sessionID,
                                        direction: .up,
                                        hovering: hovering
                                    )
                                }
                            Spacer(minLength: 0)
                            Color.clear
                                .frame(height: verticalTrigger)
                                .onHover { hovering in
                                    niriHandleEdgeHover(
                                        sessionID: sessionID,
                                        direction: .down,
                                        hovering: hovering
                                    )
                                }
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    func niriHandleEdgeHover(
        sessionID: UUID,
        direction: NiriEdgeAutoScrollDirection,
        hovering: Bool
    ) {
        if hovering {
            niriStartEdgeAutoScroll(sessionID: sessionID, direction: direction)
        } else if niriEdgeAutoScrollBySession[sessionID]?.direction == direction {
            niriCancelEdgeAutoScroll(sessionID: sessionID)
        }
    }

    func niriStartEdgeAutoScroll(sessionID: UUID, direction: NiriEdgeAutoScrollDirection) {
        guard sessionService.niriLayout(for: sessionID).isOverviewOpen else { return }
        guard niriDraggedItemBySession[sessionID] != nil else { return }
        if niriEdgeAutoScrollBySession[sessionID]?.direction == direction {
            return
        }

        niriCancelEdgeAutoScroll(sessionID: sessionID)

        let niriSettings = sessionService.settings.niri
        let useWorkspaceSettings = direction == .up || direction == .down
        let delayMs = useWorkspaceSettings ? niriSettings.edgeWorkspaceSwitch.delayMs : niriSettings.edgeViewScroll.delayMs
        let maxSpeed = useWorkspaceSettings ? niriSettings.edgeWorkspaceSwitch.maxSpeed : niriSettings.edgeViewScroll.maxSpeed
        let stepDistance: CGFloat = useWorkspaceSettings ? 460 : 520
        let interval = max(0.06, min(0.35, Double(stepDistance / max(CGFloat(maxSpeed), 1))))

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            while !Task.isCancelled {
                guard niriDraggedItemBySession[sessionID] != nil else { return }
                switch direction {
                case .left:
                    sessionService.niriFocusNeighbor(sessionID: sessionID, horizontal: -1)
                case .right:
                    sessionService.niriFocusNeighbor(sessionID: sessionID, horizontal: 1)
                case .up:
                    sessionService.focusNiriWorkspaceUp(sessionID: sessionID)
                case .down:
                    sessionService.focusNiriWorkspaceDown(sessionID: sessionID)
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        niriEdgeAutoScrollBySession[sessionID] = NiriEdgeAutoScrollRuntime(
            direction: direction,
            task: task
        )
    }

    func niriCancelEdgeAutoScroll(sessionID: UUID) {
        niriEdgeAutoScrollBySession[sessionID]?.task.cancel()
        niriEdgeAutoScrollBySession.removeValue(forKey: sessionID)
    }

    func niriHandleHoverActivation(
        sessionID: UUID,
        itemID: UUID,
        isHovering: Bool
    ) {
        guard sessionService.niriLayout(for: sessionID).isOverviewOpen else { return }
        guard niriDraggedItemBySession[sessionID] != nil else { return }

        if isHovering {
            niriHoverActivateTargetBySession[sessionID] = itemID
            niriHoverActivateTaskBySession[sessionID]?.cancel()
            niriHoverActivateTaskBySession[sessionID] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard niriHoverActivateTargetBySession[sessionID] == itemID else { return }
                sessionService.niriSelectItem(sessionID: sessionID, itemID: itemID)
            }
        } else if niriHoverActivateTargetBySession[sessionID] == itemID {
            niriCancelHoverActivation(sessionID: sessionID)
        }
    }

    func niriCancelHoverActivation(sessionID: UUID) {
        niriHoverActivateTaskBySession[sessionID]?.cancel()
        niriHoverActivateTaskBySession.removeValue(forKey: sessionID)
        niriHoverActivateTargetBySession.removeValue(forKey: sessionID)
    }

    func niriBeginGesture(sessionID: UUID, inputKind: NiriPanInputKind) {
        var runtime = niriRuntimeBySession[sessionID] ?? NiriCanvasRuntimeState()
        let gestureSettings = sessionService.settings.niri.gestures

        // Capture in-flight transient offset so the new gesture starts from current visual position
        // rather than snapping to zero (velocity continuity on interrupted animations).
        runtime.cameraOffset.width += runtime.transientOffset.width
        runtime.cameraOffset.height += runtime.transientOffset.height
        runtime.transientOffset = .zero

        runtime.inputKind = inputKind
        runtime.gesture = NiriGestureState(axis: .undecided, cumulative: .zero, isActive: true)
        runtime.lastDragTranslation = .zero
        runtime.horizontalTracker = SwipeTracker(
            historyLimit: TimeInterval(gestureSettings.swipeHistoryMs) / 1000,
            deceleration: CGFloat(gestureSettings.decelerationTouchpad)
        )
        runtime.verticalTracker = SwipeTracker(
            historyLimit: TimeInterval(gestureSettings.swipeHistoryMs) / 1000,
            deceleration: CGFloat(gestureSettings.decelerationTouchpad)
        )
        niriRuntimeBySession[sessionID] = runtime
    }

    func niriHandleOneFingerDragChanged(sessionID: UUID, translation: CGSize) {
        var runtime = niriRuntimeBySession[sessionID] ?? NiriCanvasRuntimeState()
        if !runtime.gesture.isActive {
            niriBeginGesture(sessionID: sessionID, inputKind: .oneFingerDrag)
            runtime = niriRuntimeBySession[sessionID] ?? runtime
        }
        let delta = CGSize(
            width: translation.width - runtime.lastDragTranslation.width,
            height: translation.height - runtime.lastDragTranslation.height
        )
        runtime.lastDragTranslation = translation
        niriRuntimeBySession[sessionID] = runtime
        niriHandleGestureDelta(sessionID: sessionID, delta: delta)
    }

    func niriHandleTwoFingerScrollChanged(sessionID: UUID, delta: CGSize) {
        var runtime = niriRuntimeBySession[sessionID] ?? NiriCanvasRuntimeState()
        if !runtime.gesture.isActive {
            niriBeginGesture(sessionID: sessionID, inputKind: .twoFingerScroll)
            runtime = niriRuntimeBySession[sessionID] ?? runtime
        }
        let translated = CGSize(width: -delta.width, height: -delta.height)
        niriHandleGestureDelta(sessionID: sessionID, delta: translated)
    }

    func niriHandleGestureDelta(sessionID: UUID, delta: CGSize) {
        guard var runtime = niriRuntimeBySession[sessionID] else { return }
        let now = Date.timeIntervalSinceReferenceDate

        runtime.gesture.cumulative.width += delta.width
        runtime.gesture.cumulative.height += delta.height

        if runtime.gesture.axis == .undecided {
            let threshold = CGFloat(sessionService.settings.niri.gestures.decisionThresholdPx)
            let distance = hypot(runtime.gesture.cumulative.width, runtime.gesture.cumulative.height)
            if distance < threshold {
                niriRuntimeBySession[sessionID] = runtime
                return
            }

            if abs(runtime.gesture.cumulative.width) >= abs(runtime.gesture.cumulative.height) {
                runtime.gesture.axis = .horizontal
                runtime.horizontalTracker.push(delta: runtime.gesture.cumulative.width, at: now)
                runtime.transientOffset = CGSize(width: runtime.horizontalTracker.position, height: 0)
            } else {
                runtime.gesture.axis = .vertical
                runtime.verticalTracker.push(delta: runtime.gesture.cumulative.height, at: now)
                runtime.transientOffset = CGSize(width: 0, height: runtime.verticalTracker.position)
            }
            niriRuntimeBySession[sessionID] = runtime
            return
        }

        switch runtime.gesture.axis {
        case .horizontal:
            runtime.horizontalTracker.push(delta: delta.width, at: now)
            runtime.transientOffset = CGSize(width: runtime.horizontalTracker.position, height: 0)
        case .vertical:
            runtime.verticalTracker.push(delta: delta.height, at: now)
            runtime.transientOffset = CGSize(width: 0, height: runtime.verticalTracker.position)
        case .undecided:
            break
        }

        niriRuntimeBySession[sessionID] = runtime
    }

    func niriEndGesture(
        sessionID: UUID,
        layout: NiriCanvasLayout,
        metrics: NiriCanvasMetrics
    ) {
        guard var runtime = niriRuntimeBySession[sessionID], runtime.gesture.isActive else { return }
        runtime.gesture.isActive = false
        runtime.lastDragTranslation = .zero
        niriRuntimeBySession[sessionID] = runtime

        switch runtime.gesture.axis {
        case .horizontal:
            niriFinishHorizontalGesture(
                sessionID: sessionID,
                layout: layout,
                runtime: runtime,
                metrics: metrics
            )
        case .vertical:
            niriFinishVerticalGesture(
                sessionID: sessionID,
                layout: layout,
                runtime: runtime,
                metrics: metrics
            )
        case .undecided:
            niriAnimateGestureReset(
                sessionID: sessionID,
                axis: .undecided,
                initialVelocity: 0
            )
        }
    }

    func niriFinishHorizontalGesture(
        sessionID: UUID,
        layout: NiriCanvasLayout,
        runtime: NiriCanvasRuntimeState,
        metrics: NiriCanvasMetrics
    ) {
        let velocity = runtime.horizontalTracker.velocity()
        guard niriShouldSnapForVelocity(velocity) else {
            niriCommitFreePanEnd(
                sessionID: sessionID,
                runtime: runtime,
                axis: .horizontal
            )
            return
        }

        guard let workspaceIndex = niriActiveWorkspaceIndex(layout: layout),
              workspaceIndex < layout.workspaces.count else {
            niriCommitFreePanEnd(
                sessionID: sessionID,
                runtime: runtime,
                axis: .horizontal
            )
            return
        }
        let columns = layout.workspaces[workspaceIndex].columns
        guard !columns.isEmpty else {
            niriCommitFreePanEnd(
                sessionID: sessionID,
                runtime: runtime,
                axis: .horizontal
            )
            return
        }
        let currentColumnIndex = niriActiveColumnIndex(layout: layout, workspaceIndex: workspaceIndex) ?? 0
        let projected = runtime.cameraOffset.width + runtime.horizontalTracker.projectedEndPosition()
        let activeColumnWidth = niriColumnWidth(column: columns[currentColumnIndex], metrics: metrics)
        let step = activeColumnWidth + metrics.columnSpacing
        let projectedShift = Int((projected / max(step, 1)).rounded())
        let targetColumnIndex = max(0, min(columns.count - 1, currentColumnIndex - projectedShift))
        let indexDelta = targetColumnIndex - currentColumnIndex
        let continuityOffset = runtime.cameraOffset.width + runtime.horizontalTracker.position + CGFloat(indexDelta) * step

        var nextRuntime = runtime
        nextRuntime.cameraOffset = CGSize(width: 0, height: runtime.cameraOffset.height)
        nextRuntime.transientOffset = CGSize(width: continuityOffset, height: runtime.transientOffset.height)
        nextRuntime.horizontalTracker.reset()
        nextRuntime.verticalTracker.reset()
        niriRuntimeBySession[sessionID] = nextRuntime

        if targetColumnIndex != currentColumnIndex,
           let targetItemID = columns[targetColumnIndex].focusedItemID ?? columns[targetColumnIndex].items.first?.id {
            sessionService.niriSelectItem(sessionID: sessionID, itemID: targetItemID)
        }

        let initialVelocity = velocity / max(step, 1)
        niriAnimateGestureReset(
            sessionID: sessionID,
            axis: .horizontal,
            initialVelocity: initialVelocity
        )
    }

    func niriFinishVerticalGesture(
        sessionID: UUID,
        layout: NiriCanvasLayout,
        runtime: NiriCanvasRuntimeState,
        metrics: NiriCanvasMetrics
    ) {
        let velocity = runtime.verticalTracker.velocity()
        guard niriShouldSnapForVelocity(velocity) else {
            niriCommitFreePanEnd(
                sessionID: sessionID,
                runtime: runtime,
                axis: .vertical
            )
            return
        }

        guard let currentWorkspaceIndex = niriActiveWorkspaceIndex(layout: layout),
              currentWorkspaceIndex < layout.workspaces.count else {
            niriCommitFreePanEnd(
                sessionID: sessionID,
                runtime: runtime,
                axis: .vertical
            )
            return
        }
        let projected = runtime.cameraOffset.height + runtime.verticalTracker.projectedEndPosition()
        let step = niriWorkspaceStep(layout: layout, metrics: metrics, workspaceIndex: currentWorkspaceIndex)
        let projectedShift = Int((projected / max(step, 1)).rounded())
        let targetWorkspaceIndex = max(0, min(layout.workspaces.count - 1, currentWorkspaceIndex - projectedShift))
        let indexDelta = targetWorkspaceIndex - currentWorkspaceIndex
        let continuityOffset = runtime.cameraOffset.height + runtime.verticalTracker.position + CGFloat(indexDelta) * step

        var nextRuntime = runtime
        nextRuntime.cameraOffset = CGSize(width: runtime.cameraOffset.width, height: 0)
        nextRuntime.transientOffset = CGSize(width: runtime.transientOffset.width, height: continuityOffset)
        nextRuntime.horizontalTracker.reset()
        nextRuntime.verticalTracker.reset()
        niriRuntimeBySession[sessionID] = nextRuntime

        if indexDelta > 0 {
            for _ in 0..<indexDelta {
                sessionService.focusNiriWorkspaceDown(sessionID: sessionID)
            }
        } else if indexDelta < 0 {
            for _ in 0..<(-indexDelta) {
                sessionService.focusNiriWorkspaceUp(sessionID: sessionID)
            }
        }

        let initialVelocity = velocity / max(step, 1)
        niriAnimateGestureReset(
            sessionID: sessionID,
            axis: .vertical,
            initialVelocity: initialVelocity
        )
    }

    func niriShouldSnapForVelocity(_ velocity: CGFloat) -> Bool {
        guard sessionService.settings.niri.snapEnabled else { return false }
        let threshold = CGFloat(sessionService.settings.niri.gestures.snapVelocityThresholdPxPerSec)
        return abs(velocity) >= threshold
    }

    func niriCommitFreePanEnd(
        sessionID: UUID,
        runtime: NiriCanvasRuntimeState,
        axis: NiriGestureAxis
    ) {
        var nextRuntime = runtime
        switch axis {
        case .horizontal:
            nextRuntime.cameraOffset.width += runtime.horizontalTracker.position
        case .vertical:
            nextRuntime.cameraOffset.height += runtime.verticalTracker.position
        case .undecided:
            break
        }

        nextRuntime.transientOffset = .zero
        nextRuntime.horizontalTracker.reset()
        nextRuntime.verticalTracker.reset()
        nextRuntime.lastDragTranslation = .zero
        nextRuntime.gesture = NiriGestureState(axis: .undecided, cumulative: .zero, isActive: false)
        niriRuntimeBySession[sessionID] = nextRuntime
    }

    func niriAnimateGestureReset(
        sessionID: UUID,
        axis: NiriGestureAxis,
        initialVelocity: CGFloat
    ) {
        let gestures = sessionService.settings.niri.gestures
        let spring: Animation
        switch axis {
        case .vertical:
            // Critical damping = 2 * sqrt(mass * stiffness). damping setting is the ratio.
            let criticalDamping = 2.0 * sqrt(1.0 * gestures.verticalSpringStiffness)
            spring = .interpolatingSpring(
                mass: 1,
                stiffness: gestures.verticalSpringStiffness,
                damping: criticalDamping * gestures.verticalSpringDamping,
                initialVelocity: initialVelocity
            )
        case .horizontal, .undecided:
            let criticalDamping = 2.0 * sqrt(1.0 * gestures.horizontalSpringStiffness)
            spring = .interpolatingSpring(
                mass: 1,
                stiffness: gestures.horizontalSpringStiffness,
                damping: criticalDamping * gestures.horizontalSpringDamping,
                initialVelocity: initialVelocity
            )
        }

        withAnimation(spring) {
            var runtime = niriRuntimeBySession[sessionID] ?? NiriCanvasRuntimeState()
            runtime.transientOffset = .zero
            runtime.lastDragTranslation = .zero
            runtime.gesture = NiriGestureState(axis: .undecided, cumulative: .zero, isActive: false)
            niriRuntimeBySession[sessionID] = runtime
        }
    }

    func niriHandlePointerMoved(sessionID: UUID, location: CGPoint, containerSize: CGSize) {
        guard !sessionService.settings.niri.hotCorners.isEmpty else { return }
        var runtime = niriRuntimeBySession[sessionID] ?? NiriCanvasRuntimeState()
        if runtime.gesture.isActive || niriDraggedItemBySession[sessionID] != nil {
            return
        }
        let inConfiguredCorner = niriPointIsInConfiguredHotCorner(
            location: location,
            containerSize: containerSize
        )

        if inConfiguredCorner {
            if runtime.hotCornerArmed {
                runtime.hotCornerArmed = false
                niriRuntimeBySession[sessionID] = runtime
                sessionService.toggleNiriOverview(sessionID: sessionID)
            }
        } else {
            runtime.hotCornerArmed = true
            niriRuntimeBySession[sessionID] = runtime
        }
    }

    func niriPointIsInConfiguredHotCorner(location: CGPoint, containerSize: CGSize) -> Bool {
        let trigger: CGFloat = 14
        let corners = sessionService.settings.niri.hotCorners
        return corners.contains { corner in
            switch corner {
            case .topLeft:
                return location.x <= trigger && location.y >= containerSize.height - trigger
            case .topRight:
                return location.x >= containerSize.width - trigger && location.y >= containerSize.height - trigger
            case .bottomLeft:
                return location.x <= trigger && location.y <= trigger
            case .bottomRight:
                return location.x >= containerSize.width - trigger && location.y <= trigger
            }
        }
    }

}
