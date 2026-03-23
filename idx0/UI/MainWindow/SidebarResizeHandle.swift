import AppKit
import SwiftUI

// MARK: - Resize Handle (shared)

struct SidebarResizeHandle: View {
    @Environment(\.themeColors) private var themeColors
    @Binding var width: CGFloat
    let min: CGFloat
    let max: CGFloat

    var body: some View {
        ResizeHandleRepresentable(
            width: $width,
            min: min,
            max: max,
            dividerColor: themeColors.divider
        )
        .frame(width: 7)
    }
}

struct ResizeHandleRepresentable: NSViewRepresentable {
    @Binding var width: CGFloat
    let min: CGFloat
    let max: CGFloat
    let dividerColor: Color

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.currentWidth = width
        view.minWidth = min
        view.maxWidth = max
        view.dividerNSColor = NSColor(dividerColor)
        view.onCommit = { newWidth in
            width = newWidth
        }
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        nsView.currentWidth = width
        nsView.minWidth = min
        nsView.maxWidth = max
        nsView.dividerNSColor = NSColor(dividerColor)
        nsView.needsDisplay = true
        nsView.onCommit = { newWidth in
            width = newWidth
        }
    }
}

final class ResizeHandleNSView: NSView {
    var currentWidth: CGFloat = 220
    var minWidth: CGFloat = 140
    var maxWidth: CGFloat = 360
    var dividerNSColor: NSColor = .separatorColor
    var onCommit: ((CGFloat) -> Void)?

    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startX = event.locationInWindow.x
        startWidth = currentWidth
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - startX
        let newWidth = Swift.min(maxWidth, Swift.max(minWidth, startWidth + delta))
        onCommit?(newWidth)
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineRect = NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
        dividerNSColor.setFill()
        lineRect.fill()
    }
}
