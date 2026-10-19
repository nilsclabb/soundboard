import AppKit
import SwiftUI

enum NotchState {
    case closed, hovered, open
}

@MainActor
@Observable
final class NotchController {
    private(set) var state = NotchState.closed
    private(set) var notchSize = CGSize(width: 185, height: 32)
    private(set) var hasNotch = false
    var isEnabled = true {
        didSet {
            setState(.closed)
            if isEnabled { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
    }

    @ObservationIgnored private let store: PadStore
    @ObservationIgnored private let panel = NotchPanel()
    @ObservationIgnored private var pendingClose: Task<Void, Never>?
    @ObservationIgnored private var isMenuOpen = false
    private let panelSize = CGSize(width: 520, height: 290)

    init(store: PadStore) {
        self.store = store
        let host = FirstMouseHostingView(rootView: NotchView(controller: self, store: store))
        host.sizingOptions = []
        panel.contentView = host
        positionPanel()
        panel.orderFrontRegardless()
        installMonitors()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }
        // Menus can extend past the board, so the mouse leaving it there must not close it.
        for (name, isOpen) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isMenuOpen = isOpen }
            }
        }
    }

    func size(for state: NotchState) -> CGSize {
        switch state {
        case .closed: notchSize
        case .hovered: CGSize(width: notchSize.width + 50, height: notchSize.height + 26)
        case .open: CGSize(width: 440, height: notchSize.height + 198)
        }
    }

    func open() {
        setState(.open)
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func positionPanel() {
        guard let screen else { return }
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            hasNotch = true
            notchSize = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            hasNotch = false
            notchSize = CGSize(width: 185, height: max(frame.maxY - screen.visibleFrame.maxY, 24))
        }
        panel.setFrame(
            NSRect(x: frame.midX - panelSize.width / 2, y: frame.maxY - panelSize.height,
                   width: panelSize.width, height: panelSize.height),
            display: true
        )
    }

    private func hitRect(for state: NotchState) -> NSRect {
        guard let screen else { return .zero }
        let size = size(for: state)
        let rect = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                          width: size.width, height: size.height)
        let tolerance: CGFloat = state == .closed ? 0 : 10
        return rect.insetBy(dx: -tolerance, dy: -tolerance)
    }

    private func installMonitors() {
        let mouse: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        _ = NSEvent.addGlobalMonitorForEvents(matching: mouse) { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.mouseMoved(dragging: dragging) }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: mouse) { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.mouseMoved(dragging: dragging) }
            return event
        }
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.setState(.closed) }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let isCommand = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, characters: characters, isCommand: isCommand) ?? false
            }
            return handled ? nil : event
        }
    }

    private func mouseMoved(dragging: Bool) {
        guard isEnabled, !isMenuOpen else { return }
        let inside = hitRect(for: state).contains(NSEvent.mouseLocation)
        if inside {
            pendingClose?.cancel()
            pendingClose = nil
        }
        switch state {
        case .closed where inside: setState(dragging ? .open : .hovered)
        case .hovered where dragging && inside: setState(.open)
        case .hovered where !inside: scheduleClose(after: .milliseconds(120))
        case .open where !inside: scheduleClose(after: .milliseconds(450))
        default: break
        }
    }

    private func scheduleClose(after delay: Duration) {
        guard pendingClose == nil else { return }
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.setState(.closed)
        }
    }

    private func handleKey(keyCode: UInt16, characters: String?, isCommand: Bool) -> Bool {
        guard state == .open, panel.isKeyWindow, !(panel.firstResponder is NSText) else { return false }
        if isCommand {
            guard characters == "v" else { return false }
            pasteLink()
            return true
        }
        let (escape, leftArrow, rightArrow, space, enter, keypadEnter): (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16) = (53, 123, 124, 49, 36, 76)
        switch keyCode {
        case escape: setState(.closed)
        case leftArrow: store.selectAdjacentPreset(-1)
        case rightArrow: store.selectAdjacentPreset(1)
        case space, enter, keypadEnter: store.stopAll()
        default: break
        }
        if [escape, leftArrow, rightArrow, space, enter, keypadEnter].contains(keyCode) { return true }
        guard let digit = characters.flatMap({ Int($0) }), (1...PadStore.slotCount).contains(digit) else { return false }
        store.play(digit - 1)
        return true
    }

    private func pasteLink() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let link = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(link.scheme),
              let slot = store.pads.indices.first(where: { store.pads[$0] == nil && !store.isDownloading($0) }) else {
            return NSSound.beep()
        }
        TrimWindow.importLink(link, to: slot, store: store)
    }

    private func setState(_ newState: NotchState) {
        pendingClose?.cancel()
        pendingClose = nil
        guard newState != state else { return }
        if newState != .closed {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { state = newState }
        panel.ignoresMouseEvents = newState == .closed
        if newState == .open {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Re-ordering is the only way to hand key status back to the app the user was typing in.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}

private final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
