import SwiftUI
import AVKit
import UniformTypeIdentifiers

private let shuffleOptions: [(label: String, seconds: TimeInterval)] = [
    ("1 分钟", 60),
    ("5 分钟", 300),
    ("15 分钟", 900),
    ("30 分钟", 1800),
    ("1 小时", 3600),
]

struct ContentView: View {
    @StateObject private var library = WallpaperLibrary.shared
    @ObservedObject private var engine = WallpaperEngine.shared
    @State private var activeItemURL: URL? = {
        if let path = UserDefaults.standard.string(forKey: "lastVideoPath"),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()
    @State private var showAddSheet = false
    @State private var shuffleTimer: Timer?
    @State private var isShuffleOn = UserDefaults.standard.bool(forKey: "shuffleOn")
    @State private var shuffleIndex: Int = {
        let saved = UserDefaults.standard.double(forKey: "shuffleInterval")
        if saved > 0, let idx = shuffleOptions.firstIndex(where: { $0.seconds == saved }) {
            return idx
        }
        return 1 // default: 5 min
    }()

    private var activeItem: LibraryItem? {
        guard let url = activeItemURL else { return nil }
        return library.items.first { $0.url == url }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Title bar ──
            HStack {
                if let path = Bundle.main.path(forResource: "title-icon", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text("小雷壁纸")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // ── Current status ──
            if let item = activeItem, engine.isRunning {
                HStack {
                    Image(systemName: "play.display").foregroundColor(.green)
                    Text("当前: \(item.name)")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    if isShuffleOn {
                        Text("随机中").font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }
                    Text("运行中").font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
                .padding(.horizontal, 20).padding(.top, 10)
            }

            // ── Shuffle controls ──
            if !library.items.isEmpty {
                HStack(spacing: 8) {
                    Toggle(isOn: $isShuffleOn) {
                        Text("随机切换").font(.caption)
                    }
                    .toggleStyle(.switch)
                    .onChange(of: isShuffleOn) { on in
                        UserDefaults.standard.set(on, forKey: "shuffleOn")
                        if on { startTimer() } else { killTimer() }
                    }

                    if isShuffleOn {
                        Picker("间隔", selection: $shuffleIndex) {
                            ForEach(0..<shuffleOptions.count, id: \.self) { i in
                                Text(shuffleOptions[i].label).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)
                        .onChange(of: shuffleIndex) { idx in
                            let sec = shuffleOptions[idx].seconds
                            UserDefaults.standard.set(sec, forKey: "shuffleInterval")
                            // Restart timer with new interval
                            if isShuffleOn { startTimer() }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 10)
            }

            // ── Library ──
            if library.items.isEmpty {
                emptyView
            } else {
                libraryList
            }

            // ── Bottom buttons ──
            HStack(spacing: 10) {
                Button(action: { showAddSheet = true }) {
                    Label("添加壁纸", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !library.items.isEmpty {
                    Button(action: applyRandom) {
                        Label("随手换", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if engine.isRunning {
                        Button(action: stopWallpaper) {
                            Label("停止", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 420, height: 500)
        .onAppear {
            library.loadItems()
            syncActiveItem()
            if isShuffleOn { startTimer() }
        }
        .onDisappear { killTimer() }
        .fileImporter(
            isPresented: $showAddSheet,
            allowedContentTypes: [UTType.mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    library.addVideo(from: url)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("壁纸库为空").font(.headline).foregroundColor(.secondary)
            Text("点击「添加壁纸」将 MP4 视频加入库中").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Library

    private var libraryList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(library.items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private func row(_ item: LibraryItem) -> some View {
        let isActive = activeItemURL == item.url && engine.isRunning

        return HStack(spacing: 10) {
            ThumbnailView(url: item.url)
                .frame(width: 72, height: 45)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Text(item.name)
                .font(.caption).lineLimit(1).truncationMode(.middle)

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.caption)
            } else {
                Button("设壁纸") { setWallpaper(item) }
                    .buttonStyle(.borderless).font(.caption)
                    .foregroundColor(.accentColor)
            }

            Button {
                if isActive { stopWallpaper() }
                library.removeItem(item)
            } label: {
                Image(systemName: "trash").font(.caption).foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func setWallpaper(_ item: LibraryItem) {
        activeItemURL = item.url
        UserDefaults.standard.set(item.url.path, forKey: "lastVideoPath")
        engine.start(with: item.url)
    }

    private func applyRandom() {
        guard let item = library.randomItem() else { return }
        setWallpaper(item)
    }

    private func stopWallpaper() {
        killTimer()
        engine.stop()
        syncActiveItem()
    }

    private func syncActiveItem() {
        if !engine.isRunning {
            activeItemURL = nil
        } else if activeItemURL == nil,
                  let path = UserDefaults.standard.string(forKey: "lastVideoPath"),
                  FileManager.default.fileExists(atPath: path) {
            activeItemURL = URL(fileURLWithPath: path)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        killTimer()
        let interval = shuffleOptions[shuffleIndex].seconds
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                guard self.isShuffleOn, self.library.items.count > 1 else { return }
                // Pick a random item that is NOT the current one
                let candidates = self.library.items.filter { $0.url != self.activeItemURL }
                guard let item = candidates.randomElement() ?? self.library.randomItem() else { return }
                self.setWallpaper(item)
            }
        }
    }

    private func killTimer() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
    }
}

// MARK: - Thumbnail

struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipped()
            } else {
                ZStack {
                    Color.black
                    Image(systemName: "play.rectangle").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .onAppear { generate() }
    }

    private func generate() {
        DispatchQueue.global(qos: .background).async {
            let asset = AVAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 144, height: 90)
            do {
                let cg = try gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
                let img = NSImage(cgImage: cg, size: NSSize(width: 144, height: 90))
                DispatchQueue.main.async { self.image = img }
            } catch {}
        }
    }
}
