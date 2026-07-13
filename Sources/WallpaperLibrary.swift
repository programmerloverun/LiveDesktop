import Foundation

final class WallpaperLibrary: ObservableObject {
    @Published var items: [LibraryItem] = []

    static let shared = WallpaperLibrary()

    private var libraryDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LiveDesktop/Library")
    }

    private let builtInImportKey = "builtInWallpapersImported_v1"

    init() {
        ensureDir()
        importBuiltInWallpapers()
        loadItems()
    }

    private func importBuiltInWallpapers() {
        guard !UserDefaults.standard.bool(forKey: builtInImportKey) else { return }
        guard let builtInDir = Bundle.main.url(forResource: "BuiltInWallpapers", withExtension: nil) else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: builtInDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for src in files where src.pathExtension.lowercased() == "mp4" {
            let dest = libraryDir.appendingPathComponent(src.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: src, to: dest)
            }
        }
        UserDefaults.standard.set(true, forKey: builtInImportKey)
    }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
    }

    func addVideo(from sourceURL: URL) {
        ensureDir()
        let destURL = libraryDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Avoid duplicates
        let finalName: String
        if FileManager.default.fileExists(atPath: destURL.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            let uuid = UUID().uuidString.prefix(6)
            finalName = "\(stem)_\(uuid).\(ext)"
        } else {
            finalName = sourceURL.lastPathComponent
        }

        let dest = libraryDir.appendingPathComponent(finalName)
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
        loadItems()
    }

    func removeItem(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: item.url)
        loadItems()
    }

    func randomItem() -> LibraryItem? {
        items.randomElement()
    }

    func loadItems() {
        ensureDir()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: libraryDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        items = files
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .compactMap { url in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let modDate = attrs[.modificationDate] as? Date
                else { return nil }
                return LibraryItem(url: url, addedAt: modDate)
            }
            .sorted { $0.addedAt > $1.addedAt }
    }
}

struct LibraryItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let addedAt: Date

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool { lhs.id == rhs.id }
}
