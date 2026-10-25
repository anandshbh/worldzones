import AppKit
import Combine
import SwiftUI

/// Where the panel's arrow sits, in panel coordinates.
@MainActor
final class PanelGeometry: ObservableObject {
    @Published var arrowX: CGFloat = StatusPanelController.width / 2
}

/// Owns the menu bar item and the panel under it. MenuBarExtra's window didn't shrink with its
/// content and drifted away from the menu bar when pages changed size, so the panel is placed by
/// hand: every time its content resizes, it's re-anchored just below the status item.
@MainActor
final class StatusPanelController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: Panel
    private let host: FittingHostingView
    private let blur = NSVisualEffectView()
    private let geometry = PanelGeometry()
    private var cancellables: Set<AnyCancellable> = []
    private var clickMonitor: Any?
    /// Clicking the menu bar item while open first resigns the panel (closing it); without this the
    /// same click would then reopen it.
    private var lastClose = Date.distantPast

    static let width: CGFloat = 400
    /// Space between the bottom of the menu bar and the arrow's tip.
    private static let gap: CGFloat = 1

    init(model: AppModel) {
        self.model = model
        host = FittingHostingView(rootView: AnyView(ContentView().environmentObject(model).environmentObject(geometry)))
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }

        // Blur behind, SwiftUI on top; both are cut to PopoverShape (the blur via its mask image,
        // the SwiftUI side via clipShape) so the window's shadow follows the arrow too.
        let container = NSView()
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        host.autoresizingMask = [.width, .height]
        host.onSizeChange = { [weak self] in self?.reposition() }
        container.addSubview(blur)
        container.addSubview(host)
        panel.contentView = container

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // objectWillChange fires before the new value lands, so read it on the next turn.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateButton()
                // Page switches and added cities change the panel's height; refit once SwiftUI has laid out.
                if self?.panel.isVisible == true { DispatchQueue.main.async { self?.reposition() } }
            }
            .store(in: &cancellables)
        updateButton()

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    // MARK: Menu bar item

    private func updateButton() {
        blur.material = model.glassStyle == .clear ? .hudWindow : .popover
        guard let button = statusItem.button else { return }
        if model.menuBarStyle == .icon {
            button.attributedTitle = NSAttributedString()
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "WorldZones")
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.imagePosition = .noImage
            // Monospaced digits keep the item from changing width as the time ticks.
            button.attributedTitle = NSAttributedString(string: model.menuBarText, attributes: [.font: Self.menuBarFont])
        }
    }

    private static let menuBarFont: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 0)
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }()

    // MARK: Panel

    @objc private func toggle() {
        if panel.isVisible { close() } else if Date().timeIntervalSince(lastClose) > 0.3 { open() }
    }

    private func open() {
        model.page = .zones
        reposition()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        guard panel.isVisible else { return }
        lastClose = Date()
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        model.offsetMinutes = 0
        model.draggingZoneID = nil
    }

    /// Sizes the panel to its content, pins its top edge just under the status item, and points
    /// the arrow at the item.
    private func reposition() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = host.fittingSize
        if panel.isVisible, abs(panel.frame.height - size.height) < 0.5, abs(geometry.arrowX - (anchor.midX - panel.frame.minX)) < 0.5 { return }
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - Self.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - Self.width - 8)
        let top = buttonWindow.frame.minY - Self.gap
        let arrowX = anchor.midX - x
        if geometry.arrowX != arrowX { geometry.arrowX = arrowX }
        panel.setFrame(NSRect(x: x, y: top - size.height, width: Self.width, height: size.height), display: true)
        blur.frame = panel.contentView?.bounds ?? .zero
        blur.maskImage = Self.mask(size: size, arrowX: arrowX)
        panel.invalidateShadow()
    }

    private static func mask(size: CGSize, arrowX: CGFloat) -> NSImage {
        // Flipped so the SwiftUI path's top-down coordinates draw the same way up.
        NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(PopoverShape(arrowX: arrowX).path(in: rect).cgPath)
            ctx.setFillColor(.black)
            ctx.fillPath()
            return true
        }
    }
}

/// Borderless panels can't take keyboard focus by default; the search field needs it.
private final class Panel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Reports whenever SwiftUI's preferred size changes (page switches, cities added, …).
private final class FittingHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}
