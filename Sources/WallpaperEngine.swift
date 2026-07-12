import Cocoa
import AVFoundation
import Combine

final class WallpaperEngine: NSObject, ObservableObject {
    static let shared = WallpaperEngine()

    @Published private(set) var isRunning = false

    private var entries: [CGDirectDisplayID: (window: NSWindow, layer: AVPlayerLayer)] = [:]
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var safetyTimer: Timer?
    private var currentVideoURL: URL?
    private var isLocked = false

    private var lockScreenImageDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LiveDesktop")
    }

    private var lockScreenImageURL: URL {
        lockScreenImageDir.appendingPathComponent("lockscreen.png")
    }

    private func desktopLevel() -> NSWindow.Level {
        NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    }

    /// Just below the lock screen password dialog — above the default lock wallpaper.
    /// kCGMaximumWindowLevel = Int32.max (2147483647); lock screen bg is a few levels below.
    private func lockScreenLevel() -> NSWindow.Level {
        NSWindow.Level(Int(Int32.max) - 17)
    }

    // MARK: - Start

    func start(with url: URL) {
        if isRunning {
            swap(to: url)
        } else {
            coldStart(url: url)
        }
    }

    private func coldStart(url: URL) {
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Limit resource usage for wallpaper playback
        item.preferredPeakBitRate = 4_000_000 // 4 Mbps — plenty for wallpaper

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        isRunning = true

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: CMTime.zero)
            player?.play()
        }

        setupAllScreens()
        player.play()
        startObservers()
        currentVideoURL = url
        updateLockScreenImage(for: url)
    }

    private func swap(to url: URL) {
        guard let player else { return }

        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }

        player.pause()

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 4_000_000

        player.replaceCurrentItem(with: item)

        // Seek to the first frame so every screen's layer gets a clean visual
        let startTime = CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            for (_, entry) in self.entries {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                entry.layer.frame = entry.window.contentView?.bounds ?? entry.layer.frame
                CATransaction.commit()
            }
            player.play()
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: CMTime.zero)
            player?.play()
        }

        currentVideoURL = url
        // Delay to let the new item load before capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateLockScreenImage(for: url)
        }
    }

    // MARK: - Lock Screen Image

    /// Capture a frame from the video and set it as the system desktop wallpaper.
    /// Our video window sits on top of the desktop, so the user sees the video.
    /// When the screen locks, the video window is hidden and the system shows the
    /// lock screen — which uses this static image, creating a seamless transition.
    private func updateLockScreenImage(for url: URL) {
        let imageDir = lockScreenImageDir
        let imageURL = lockScreenImageURL
        DispatchQueue.global(qos: .background).async {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 3840, height: 2160)

            let time = CMTime(seconds: 1, preferredTimescale: 600)
            guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else {
                print("[LiveDesktop] Failed to capture frame for lock screen")
                return
            }

            let png = NSBitmapImageRep(cgImage: cg)
            png.size = NSSize(width: cg.width, height: cg.height)
            guard let data = png.representation(using: .png, properties: [:]) else { return }

            try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
            do {
                try data.write(to: imageURL)
                print("[LiveDesktop] Lock screen image saved: \(imageURL.path)")
            } catch {
                print("[LiveDesktop] Failed to write lock screen image: \(error)")
                return
            }

            for screen in NSScreen.screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
                    print("[LiveDesktop] Set desktop image for screen: \(screen)")
                } catch {
                    print("[LiveDesktop] Failed to set desktop image: \(error)")
                }
            }

            // Sync lock screen wallpaper in the system store
            self.syncLockScreenToDesktop(imagePath: imageURL.path)
        }
    }

    /// Set the lock screen wallpaper to match the desktop image.
    /// macOS Ventura+ stores desktop and lock screen wallpapers separately —
    /// NSWorkspace only sets the desktop. We write the lock screen entry directly
    /// to the wallpaper store so both match.
    private func syncLockScreenToDesktop(imagePath: String) {
        DispatchQueue.global(qos: .background).async {
            let storeURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

            guard let data = try? Data(contentsOf: storeURL),
                  var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return }

            let imageURLEncoded = "file://" + imagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            let imageConfig: [String: Any] = [
                "type": "imageFile",
                "url": ["relative": imageURLEncoded]
            ]
            let imageConfigData = (try? PropertyListSerialization.data(fromPropertyList: imageConfig, format: .binary, options: 0)) ?? Data()

            // Get the color/placement options from the desktop entry (created by NSWorkspace)
            var desktopOptions: Data?
            if let displays = plist["Displays"] as? [String: [String: Any]],
               let firstDisplay = displays.values.first,
               let desktop = firstDisplay["Desktop"] as? [String: Any],
               let content = desktop["Content"] as? [String: Any],
               let opts = content["EncodedOptionValues"] as? Data {
                desktopOptions = opts
            } else if let global = plist["AllSpacesAndDisplays"] as? [String: Any],
                      let idleEntry = global["Idle"] as? [String: Any] ?? global["Linked"] as? [String: Any],
                      let content = idleEntry["Content"] as? [String: Any],
                      let opts = content["EncodedOptionValues"] as? Data {
                desktopOptions = opts
            }

            // Remove per-display lock screen entries — the global one takes priority when present
            if var displays = plist["Displays"] as? [String: [String: Any]] {
                for (uuid, var modes) in displays {
                    modes.removeValue(forKey: "Idle")
                    modes.removeValue(forKey: "Linked")
                    displays[uuid] = modes
                }
                plist["Displays"] = displays
            }

            // Write a global Idle entry pointing to our image
            let idleContent: [String: Any] = [
                "Choices": [[
                    "Configuration": imageConfigData,
                    "Files": [],
                    "Provider": "com.apple.wallpaper.choice.image"
                ]],
                "EncodedOptionValues": desktopOptions ?? Data()
            ]
            plist["AllSpacesAndDisplays"] = [
                "Idle": [
                    "Content": idleContent,
                    "LastSet": Date(),
                    "LastUse": Date()
                ],
                "Type": "idle"
            ] as [String: Any]

            guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            else { return }
            try? newData.write(to: storeURL, options: .atomic)

            // Restart WallpaperAgent so it reads our updated store
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["WallpaperAgent"]
            task.launch()
            task.waitUntilExit()
            print("[LiveDesktop] Lock screen synced")
        }
    }

    // MARK: - Stop

    func stop() {
        player?.pause()
        player = nil

        for (_, entry) in entries {
            entry.window.close()
        }
        entries.removeAll()

        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }

        stopObservers()
        isRunning = false
    }

    // MARK: - Observers

    private func startObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        // Safety timer: 5 seconds (was 2s — less CPU overhead)
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.bumpAll()
        }
    }

    private func stopObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    @objc private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.player?.play()
            self?.bumpAll()
        }
    }

    @objc private func handleSleep() {
        // Only pause if screens slept from idle timeout, not from lock
        if !isLocked {
            player?.pause()
        }
    }

    @objc private func handleLock() {
        isLocked = true
        let level = lockScreenLevel()
        for (_, e) in entries {
            e.window.level = level
            e.window.orderFront(nil)
        }
        // Keep video playing on lock screen
        player?.play()
    }

    @objc private func handleUnlock() {
        isLocked = false
        let level = desktopLevel()
        for (_, e) in entries {
            e.window.level = level
        }
    }

    @objc private func handleDisplayChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupAllScreens()
            self?.player?.play()
        }
    }

    // MARK: - Screens

    private func screenID(_ s: NSScreen) -> CGDirectDisplayID? {
        s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func setupAllScreens() {
        guard let player else { return }
        let current = Set(NSScreen.screens.compactMap { screenID($0) })

        for id in entries.keys where !current.contains(id) {
            entries[id]?.window.close()
            entries.removeValue(forKey: id)
        }

        for screen in NSScreen.screens {
            guard let id = screenID(screen) else { continue }
            if let e = entries[id] {
                e.window.setFrame(screen.frame, display: true)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                e.layer.frame = e.window.contentView!.bounds
                CATransaction.commit()
            } else {
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.level = isLocked ? lockScreenLevel() : desktopLevel()
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                window.isOpaque = true
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.isReleasedWhenClosed = false
                window.backgroundColor = .black

                let layer = AVPlayerLayer(player: player)
                layer.frame = window.contentView!.bounds
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.videoGravity = .resizeAspectFill

                window.contentView?.wantsLayer = true
                window.contentView?.layer?.addSublayer(layer)
                window.orderFront(nil)

                entries[id] = (window, layer)
            }
        }
    }

    // MARK: - Heartbeat (lightweight)

    private func bumpAll() {
        guard let player else { return }

        // Only call play() if actually paused/stopped (avoid useless work)
        if player.timeControlStatus == .paused || player.rate == 0 {
            player.play()
        }

        let targetLevel = isLocked ? lockScreenLevel() : desktopLevel()
        for (_, e) in entries {
            // Minimize work: skip if everything is fine
            if e.window.isVisible,
               e.window.level == targetLevel,
               e.layer.superlayer != nil {
                continue
            }

            if !e.window.isVisible { e.window.orderFront(nil) }
            if e.window.level != targetLevel { e.window.level = targetLevel }
            if e.layer.superlayer == nil {
                e.window.contentView?.layer?.addSublayer(e.layer)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            e.layer.frame = e.window.contentView!.bounds
            CATransaction.commit()
        }
    }
}
