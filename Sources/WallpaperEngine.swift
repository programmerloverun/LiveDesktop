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

    private func desktopLevel() -> NSWindow.Level {
        NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
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
            // Force all layers to display the new frame, preventing
            // the second display from showing a mix of old + new frames
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

        // Safety timer: 5 seconds (was 2s — less CPU overhead)
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.bumpAll()
        }
    }

    private func stopObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
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
        // Pause during display sleep to save energy
        player?.pause()
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
                window.level = desktopLevel()
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

        let targetLevel = desktopLevel()
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
