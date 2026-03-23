import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

 struct BrowserSplitResizeHandle: View {
    enum Axis {
        case horizontal
        case vertical
    }

    @Environment(\.themeColors) private var tc

    let axis: Axis
    let totalSize: CGFloat
    let fraction: Double
    let onFractionChanged: (Double) -> Void

    var body: some View {
        BrowserSplitResizeHandleRepresentable(
            axis: axis,
            totalSize: totalSize,
            fraction: fraction,
            validFractionRange: fractionRange,
            dividerColor: tc.divider,
            onFractionChanged: onFractionChanged
        )
        .frame(
            maxWidth: axis == .vertical ? .infinity : nil,
            maxHeight: axis == .horizontal ? .infinity : nil
        )
        .frame(
            width: axis == .horizontal ? 7 : nil,
            height: axis == .vertical ? 7 : nil
        )
    }

    private var fractionRange: ClosedRange<Double> {
        let globalLower = 0.2
        let globalUpper = 0.8
        guard totalSize > 0 else { return globalLower...globalUpper }

        let paneLower: Double
        let paneUpper: Double

        switch axis {
        case .horizontal:
            paneLower = Double(280.0 / totalSize)
            paneUpper = Double((totalSize - 280.0) / totalSize)
        case .vertical:
            paneLower = Double(180.0 / totalSize)
            paneUpper = Double((totalSize - 220.0) / totalSize)
        }

        let lower = max(globalLower, paneLower)
        let upper = min(globalUpper, paneUpper)
        guard lower <= upper else { return globalLower...globalUpper }
        return lower...upper
    }
}

 struct BrowserSplitResizeHandleRepresentable: NSViewRepresentable {
    let axis: BrowserSplitResizeHandle.Axis
    let totalSize: CGFloat
    let fraction: Double
    let validFractionRange: ClosedRange<Double>
    let dividerColor: Color
    let onFractionChanged: (Double) -> Void

    func makeNSView(context: Context) -> BrowserSplitResizeNSView {
        let view = BrowserSplitResizeNSView()
        view.axis = axis
        view.totalSize = totalSize
        view.currentFraction = fraction
        view.validFractionRange = validFractionRange
        view.dividerNSColor = NSColor(dividerColor)
        view.onFractionChanged = onFractionChanged
        return view
    }

    func updateNSView(_ nsView: BrowserSplitResizeNSView, context: Context) {
        nsView.axis = axis
        nsView.totalSize = totalSize
        nsView.currentFraction = fraction
        nsView.validFractionRange = validFractionRange
        nsView.dividerNSColor = NSColor(dividerColor)
        nsView.onFractionChanged = onFractionChanged
        nsView.needsDisplay = true
        nsView.discardCursorRects()
        nsView.resetCursorRects()
    }
}

 final class BrowserSplitResizeNSView: NSView {
    var axis: BrowserSplitResizeHandle.Axis = .horizontal
    var totalSize: CGFloat = 0
    var currentFraction: Double = 0.42
    var validFractionRange: ClosedRange<Double> = 0.2...0.8
    var dividerNSColor: NSColor = .separatorColor
    var onFractionChanged: ((Double) -> Void)?

    private var dragStartInWindow: NSPoint?
    private var startFraction: Double = 0.42

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        switch axis {
        case .horizontal:
            addCursorRect(bounds, cursor: .resizeLeftRight)
        case .vertical:
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStartInWindow = event.locationInWindow
        startFraction = currentFraction
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartInWindow, totalSize > 0 else { return }

        let delta: CGFloat
        switch axis {
        case .horizontal:
            delta = -(event.locationInWindow.x - dragStartInWindow.x)
        case .vertical:
            delta = event.locationInWindow.y - dragStartInWindow.y
        }

        let nextFraction = startFraction + Double(delta / totalSize)
        let clamped = min(validFractionRange.upperBound, max(validFractionRange.lowerBound, nextFraction))
        onFractionChanged?(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        dragStartInWindow = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        _ = dirtyRect
        let lineRect: NSRect
        switch axis {
        case .horizontal:
            lineRect = NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
        case .vertical:
            lineRect = NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        }
        dividerNSColor.setFill()
        lineRect.fill()
    }
}
