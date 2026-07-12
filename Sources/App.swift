import SwiftUI
import AppKit

@main
struct LiveDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 420)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - Window delegate: intercept close → hide

final class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of closing — so the user can reopen from Dock
        sender.orderOut(nil)
        return false
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Attach window delegate after SwiftUI creates the window
        DispatchQueue.main.async { [weak self] in
            guard let window = NSApp.windows.first(where: {
                $0.className.contains("SwiftUI") || $0.title.contains("LiveDesktop")
            }) ?? NSApp.windows.first
            else { return }

            let delegate = WindowDelegate()
            self?.windowDelegate = delegate
            window.delegate = delegate
        }

        // Restore last wallpaper on launch
        if let path = UserDefaults.standard.string(forKey: "lastVideoPath"),
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            WallpaperEngine.shared.start(with: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show window again when user clicks Dock/Launchpad icon
        for window in NSApp.windows {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        WallpaperEngine.shared.stop()
    }
}
