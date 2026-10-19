import AppKit
import ServiceManagement

@main
@MainActor
enum SoundboardApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private let enabledKey = "enabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [enabledKey: true])
        notch = NotchController(store: PadStore())
        statusItem = makeStatusItem()
        setEnabled(UserDefaults.standard.bool(forKey: enabledKey))
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = .menuBarLogo

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "e")
        enabled.target = self

        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let about = NSMenuItem(title: "About Soundboard", action: #selector(showAbout), keyEquivalent: "")
        about.target = self

        let menu = NSMenu()
        menu.addItem(enabled)
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Soundboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        return item
    }

    private func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        notch?.isEnabled = isEnabled
        statusItem?.button?.appearsDisabled = !isEnabled
        statusItem?.menu?.item(withTitle: "Enabled")?.state = isEnabled ? .on : .off
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        setEnabled(sender.state == .off)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel()
    }
}

private extension NSImage {
    /// The notch with an equalizer swelling out of it.
    static let menuBarLogo: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSBezierPath(roundedRect: NSRect(x: 3, y: -3, width: 12, height: 7), xRadius: 2.5, yRadius: 2.5).fill()
            for (index, height) in [4.0, 8, 6, 3].enumerated() {
                let x = 3.5 + Double(index) * 3
                NSBezierPath(roundedRect: NSRect(x: x, y: 16 - height, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Soundboard"
        return image
    }()
}
