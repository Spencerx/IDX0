import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Overview Snapshot

/// Wraps arbitrary content and shows a static bitmap snapshot while in overview mode.
/// When overview opens the current content is captured; when overview closes the snapshot
/// is held for the animation duration before restoring the live content.
struct OverviewSnapshotView<Content: View>: NSViewRepresentable {
    let isOverview: Bool
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> OverviewSnapshotContainerView {
        let container = OverviewSnapshotContainerView()
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.liveView = hostingView
        return container
    }

    func updateNSView(_ nsView: OverviewSnapshotContainerView, context: Context) {
        // Update the hosted content
        if let hostingView = nsView.liveView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
        nsView.setOverview(isOverview)
    }
}

final class OverviewSnapshotContainerView: NSView {
    var liveView: NSView?
    private var snapshotView: NSImageView?
    private var showingSnapshot = false
    private var isOverview = false
    private var snapshotRemovalItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setOverview(_ overview: Bool) {
        let wasOverview = isOverview
        isOverview = overview

        if overview && !wasOverview {
            captureSnapshot()
        } else if !overview && wasOverview {
            scheduleSnapshotRemoval()
        }
    }

    private func captureSnapshot() {
        layoutSubtreeIfNeeded()
        guard bounds.width > 0, bounds.height > 0 else { return }

        snapshotRemovalItem?.cancel()
        snapshotRemovalItem = nil

        var image: NSImage?

        // Try layer render first (captures Metal/WebKit content)
        if let liveView, let layer = liveView.layer {
            let img = NSImage(size: bounds.size)
            img.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                // Align Core Animation layer rendering with AppKit's top-left visual orientation.
                ctx.saveGState()
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
                layer.render(in: ctx)
                ctx.restoreGState()
            }
            img.unlockFocus()
            image = img
        }

        // Fallback to cacheDisplay
        if image == nil {
            let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds)
            if let rep = bitmapRep {
                cacheDisplay(in: bounds, to: rep)
                let fallback = NSImage(size: bounds.size)
                fallback.addRepresentation(rep)
                image = fallback
            }
        }

        if let image {
            let imageView = NSImageView(frame: bounds)
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            addSubview(imageView)
            snapshotView = imageView
        }

        showingSnapshot = true
        liveView?.isHidden = true
    }

    private func scheduleSnapshotRemoval() {
        snapshotRemovalItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.removeSnapshot()
        }
        snapshotRemovalItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func removeSnapshot() {
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        showingSnapshot = false
        liveView?.isHidden = false
    }
}
