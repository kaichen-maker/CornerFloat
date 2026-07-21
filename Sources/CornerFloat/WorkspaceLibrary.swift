import AppKit

enum CFL10n {
    static var usesChinese: Bool { false }

    static func text(_ chinese: String, _ english: String) -> String {
        usesChinese ? chinese : english
    }
}

struct BrowserBookmark: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var url: String
    let createdAt: Date
    var lastOpenedAt: Date
}

struct RecentDestination: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var url: String
    var visitedAt: Date
}

enum WorkspacePanelKind: String, Codable {
    case web
    // Decode-only compatibility for schema 3 and 4 libraries. CornerFloat no
    // longer creates or restores mirrored panels, but removing this raw value
    // would make one legacy panel fail decoding for the entire local library.
    case legacyMirror = "mirrorPlaceholder"
}

enum WorkspacePanelRestoreContent: Equatable {
    case web(tabURLs: [URL], selectedIndex: Int)
}

struct WorkspacePanelSnapshot: Codable, Equatable {
    var kind: WorkspacePanelKind?
    var url: String
    var tabURLs: [String]?
    var selectedTabIndex: Int?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isVisible: Bool
    var opacity: Double
    var isClickThrough: Bool
    var edgeAutoHideEnabled: Bool?

    init(
        url: String,
        tabURLs: [String]? = nil,
        selectedTabIndex: Int = 0,
        frame: CGRect,
        isVisible: Bool,
        opacity: Double,
        isClickThrough: Bool,
        edgeAutoHideEnabled: Bool = false
    ) {
        self.kind = .web
        self.url = url
        self.tabURLs = tabURLs ?? [url]
        self.selectedTabIndex = selectedTabIndex
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = frame.width
        self.height = frame.height
        self.isVisible = isVisible
        self.opacity = opacity
        self.isClickThrough = isClickThrough
        self.edgeAutoHideEnabled = edgeAutoHideEnabled
    }

    var panelKind: WorkspacePanelKind {
        // Schema versions 1 and 2 only stored web panels and therefore have no
        // explicit kind. Treating a missing value as web keeps those libraries
        // backward-compatible without ever interpreting a mirror as a URL.
        kind ?? .web
    }

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var savedTabURLStrings: [String] {
        let values = tabURLs?.isEmpty == false ? tabURLs! : [url]
        return values
    }

    var restoreContent: WorkspacePanelRestoreContent? {
        switch panelKind {
        case .web:
            let urls = savedTabURLStrings.compactMap { value -> URL? in
                guard let url = URL(string: value),
                      WorkspaceLibraryStore.isPersistableWebURL(url) else { return nil }
                return url
            }
            guard !urls.isEmpty else { return nil }
            return .web(
                tabURLs: urls,
                selectedIndex: min(max(selectedTabIndex ?? 0, 0), urls.count - 1)
            )
        case .legacyMirror:
            return nil
        }
    }
}

struct SavedWorkspace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var panels: [WorkspacePanelSnapshot]
}

struct WorkspaceLibrarySnapshot: Codable, Equatable {
    static let currentVersion = 4

    var version = currentVersion
    var bookmarks: [BrowserBookmark] = []
    var recents: [RecentDestination] = []
    var shortcuts: [AddressShortcut] = []
    var workspaces: [SavedWorkspace] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case bookmarks
        case recents
        case shortcuts
        case workspaces
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        bookmarks = try container.decodeIfPresent([BrowserBookmark].self, forKey: .bookmarks) ?? []
        recents = try container.decodeIfPresent([RecentDestination].self, forKey: .recents) ?? []
        shortcuts = try container.decodeIfPresent([AddressShortcut].self, forKey: .shortcuts) ?? []
        workspaces = try container.decodeIfPresent([SavedWorkspace].self, forKey: .workspaces) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encode(recents, forKey: .recents)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(workspaces, forKey: .workspaces)
    }
}

struct WorkspaceLibraryImportPreview: Equatable {
    let bookmarks: Int
    let recents: Int
    let shortcuts: Int
    let workspaces: Int

    var summary: String {
        "\(bookmarks) favorites, \(recents) recents, \(shortcuts) Quick Sites, and \(workspaces) workspaces"
    }
}

/// Reads only the compatibility boundary before decoding the evolving payload.
/// A newer app may add enum cases or reshape nested records that this version
/// cannot decode; the version still has to be honored without moving or
/// rewriting the user's library as if it were corrupt.
private struct WorkspaceLibraryVersionProbe: Decodable {
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

enum WorkspaceLibraryError: LocalizedError {
    case invalidURL
    case emptyShortcutName
    case emptyShortcutAlias
    case duplicateShortcutAlias(String)
    case emptyWorkspaceName
    case emptyWorkspace
    case libraryRequiresNewerApp(foundVersion: Int, supportedVersion: Int)
    case invalidImportFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return CFL10n.text("只能保存有效的 HTTP 或 HTTPS 网页。", "Only valid HTTP or HTTPS pages can be saved.")
        case .emptyShortcutName:
            return CFL10n.text("请输入快捷网站名称。", "Enter a name for the quick site.")
        case .emptyShortcutAlias:
            return CFL10n.text("请至少输入一个快捷词。", "Enter at least one shortcut word.")
        case let .duplicateShortcutAlias(alias):
            return CFL10n.text(
                "快捷词“\(alias)”已被另一个快捷网站使用。",
                "The shortcut word “\(alias)” is already used by another quick site."
            )
        case .emptyWorkspaceName:
            return CFL10n.text("请输入工作区名称。", "Enter a workspace name.")
        case .emptyWorkspace:
            return CFL10n.text("当前没有可保存的面板。", "There are no panels to save.")
        case let .libraryRequiresNewerApp(foundVersion, supportedVersion):
            return CFL10n.text(
                "这个资料库由更新版本的 CornerFloat 创建（版本 \(foundVersion)；当前最高支持 \(supportedVersion)）。为保护数据，资料库已设为只读。请升级 CornerFloat。",
                "This library was created by a newer CornerFloat version (schema \(foundVersion); this app supports up to \(supportedVersion)). It is read-only to protect your data. Update CornerFloat before changing Quick Sites, favorites, recents, or workspaces."
            )
        case let .invalidImportFile(detail):
            return "This is not a readable CornerFloat library file. \(detail)"
        }
    }
}

final class WorkspaceLibraryStore {
    static let maximumBookmarks = 100
    static let maximumRecents = 40
    static let maximumShortcuts = 50
    static let maximumAliasesPerShortcut = 12
    static let maximumWorkspaces = 24
    static let maximumPanelsPerWorkspace = 24
    static let maximumTabsPerPanel = 24

    private(set) var snapshot: WorkspaceLibrarySnapshot
    private(set) var loadWarning: String?
    private(set) var isReadOnly = false
    private var decodedFutureVersion: Int?
    let fileURL: URL

    init(fileURL: URL = WorkspaceLibraryStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.snapshot = WorkspaceLibrarySnapshot()
        loadFromDisk()
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("CornerFloat", isDirectory: true)
            .appendingPathComponent("Library-v1.json", isDirectory: false)
    }

    func recordRecent(title: String, url: URL, now: Date = Date()) throws {
        guard let persistedURL = URLPersistenceSanitizer.sanitizedURL(url) else {
            throw WorkspaceLibraryError.invalidURL
        }
        let normalized = Self.normalizedURLString(persistedURL)
        let cleanTitle = Self.cleanTitle(title, fallbackURL: persistedURL)

        try mutate { snapshot in
            snapshot.recents.removeAll { Self.URLsMatch($0.url, normalized) }
            snapshot.recents.insert(
                RecentDestination(id: UUID(), title: cleanTitle, url: normalized, visitedAt: now),
                at: 0
            )
            if snapshot.recents.count > Self.maximumRecents {
                snapshot.recents.removeLast(snapshot.recents.count - Self.maximumRecents)
            }
        }
    }

    @discardableResult
    func addBookmark(title: String, url: URL, now: Date = Date()) throws -> BrowserBookmark {
        guard let persistedURL = URLPersistenceSanitizer.sanitizedURL(url) else {
            throw WorkspaceLibraryError.invalidURL
        }
        let normalized = Self.normalizedURLString(persistedURL)
        let cleanTitle = Self.cleanTitle(title, fallbackURL: persistedURL)
        var result: BrowserBookmark?

        try mutate { snapshot in
            if let index = snapshot.bookmarks.firstIndex(where: { Self.URLsMatch($0.url, normalized) }) {
                snapshot.bookmarks[index].title = cleanTitle
                snapshot.bookmarks[index].url = normalized
                snapshot.bookmarks[index].lastOpenedAt = now
                result = snapshot.bookmarks[index]
            } else {
                let bookmark = BrowserBookmark(
                    id: UUID(),
                    title: cleanTitle,
                    url: normalized,
                    createdAt: now,
                    lastOpenedAt: now
                )
                snapshot.bookmarks.insert(bookmark, at: 0)
                if snapshot.bookmarks.count > Self.maximumBookmarks {
                    snapshot.bookmarks.removeLast(snapshot.bookmarks.count - Self.maximumBookmarks)
                }
                result = bookmark
            }
        }
        return result!
    }

    func markBookmarkOpened(id: UUID, now: Date = Date()) throws {
        try mutate { snapshot in
            guard let index = snapshot.bookmarks.firstIndex(where: { $0.id == id }) else { return }
            snapshot.bookmarks[index].lastOpenedAt = now
            let bookmark = snapshot.bookmarks.remove(at: index)
            snapshot.bookmarks.insert(bookmark, at: 0)
        }
    }

    func removeBookmark(id: UUID) throws {
        try mutate { snapshot in
            snapshot.bookmarks.removeAll { $0.id == id }
        }
    }

    func removeRecent(id: UUID) throws {
        try mutate { snapshot in
            snapshot.recents.removeAll { $0.id == id }
        }
    }

    func clearRecents() throws {
        try mutate { snapshot in
            snapshot.recents.removeAll()
        }
    }

    @discardableResult
    func saveShortcut(
        id: UUID? = nil,
        name: String,
        aliases: [String],
        urlString: String,
        now: Date = Date()
    ) throws -> AddressShortcut {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw WorkspaceLibraryError.emptyShortcutName }

        var seenKeys = Set<String>()
        let cleanAliases = aliases.prefix(Self.maximumAliasesPerShortcut).compactMap { raw -> String? in
            let alias = String(
                raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
            )
            let key = SmartAddressResolver.normalizedShortcutKey(alias)
            guard !alias.isEmpty, !key.isEmpty, seenKeys.insert(key).inserted else { return nil }
            return alias
        }
        guard !cleanAliases.isEmpty else { throw WorkspaceLibraryError.emptyShortcutAlias }

        guard let url = Self.validatedShortcutURL(urlString) else {
            throw WorkspaceLibraryError.invalidURL
        }

        let aliasKeys = Set(cleanAliases.map(SmartAddressResolver.normalizedShortcutKey))
        if let conflict = snapshot.shortcuts.first(where: { shortcut in
            shortcut.id != id && !aliasKeys.isDisjoint(with: shortcut.aliases.map(SmartAddressResolver.normalizedShortcutKey))
        }), let alias = cleanAliases.first(where: {
            conflict.aliases.map(SmartAddressResolver.normalizedShortcutKey)
                .contains(SmartAddressResolver.normalizedShortcutKey($0))
        }) {
            throw WorkspaceLibraryError.duplicateShortcutAlias(alias)
        }

        var result: AddressShortcut?
        try mutate { snapshot in
            if let id, let index = snapshot.shortcuts.firstIndex(where: { $0.id == id }) {
                snapshot.shortcuts[index].name = String(cleanName.prefix(80))
                snapshot.shortcuts[index].aliases = cleanAliases
                snapshot.shortcuts[index].url = Self.normalizedURLString(url)
                snapshot.shortcuts[index].updatedAt = now
                let shortcut = snapshot.shortcuts.remove(at: index)
                snapshot.shortcuts.insert(shortcut, at: 0)
                result = shortcut
            } else {
                let shortcut = AddressShortcut(
                    id: UUID(),
                    name: String(cleanName.prefix(80)),
                    aliases: cleanAliases,
                    url: Self.normalizedURLString(url),
                    createdAt: now,
                    updatedAt: now
                )
                snapshot.shortcuts.insert(shortcut, at: 0)
                if snapshot.shortcuts.count > Self.maximumShortcuts {
                    snapshot.shortcuts.removeLast(snapshot.shortcuts.count - Self.maximumShortcuts)
                }
                result = shortcut
            }
        }
        return result!
    }

    func removeShortcut(id: UUID) throws {
        try mutate { snapshot in
            snapshot.shortcuts.removeAll { $0.id == id }
        }
    }

    func shortcut(id: UUID) -> AddressShortcut? {
        snapshot.shortcuts.first { $0.id == id }
    }

    @discardableResult
    func saveWorkspace(
        name: String,
        panels: [WorkspacePanelSnapshot],
        now: Date = Date()
    ) throws -> SavedWorkspace {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw WorkspaceLibraryError.emptyWorkspaceName }
        let cleanPanels = panels.prefix(Self.maximumPanelsPerWorkspace).compactMap(Self.sanitizedPanel)
        guard !cleanPanels.isEmpty else { throw WorkspaceLibraryError.emptyWorkspace }
        var result: SavedWorkspace?

        try mutate { snapshot in
            if let index = snapshot.workspaces.firstIndex(where: {
                $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                snapshot.workspaces[index].name = cleanName
                snapshot.workspaces[index].updatedAt = now
                snapshot.workspaces[index].panels = cleanPanels
                let workspace = snapshot.workspaces.remove(at: index)
                snapshot.workspaces.insert(workspace, at: 0)
                result = workspace
            } else {
                let workspace = SavedWorkspace(
                    id: UUID(),
                    name: cleanName,
                    createdAt: now,
                    updatedAt: now,
                    panels: cleanPanels
                )
                snapshot.workspaces.insert(workspace, at: 0)
                if snapshot.workspaces.count > Self.maximumWorkspaces {
                    snapshot.workspaces.removeLast(snapshot.workspaces.count - Self.maximumWorkspaces)
                }
                result = workspace
            }
        }
        return result!
    }

    func removeWorkspace(id: UUID) throws {
        try mutate { snapshot in
            snapshot.workspaces.removeAll { $0.id == id }
        }
    }

    func workspace(id: UUID) -> SavedWorkspace? {
        snapshot.workspaces.first { $0.id == id }
    }

    /// Returns a portable, sanitized JSON representation. If this build opened
    /// a future schema read-only, export preserves the original bytes exactly
    /// instead of manufacturing an empty downgraded library.
    func exportData() throws -> Data {
        if isReadOnly, FileManager.default.fileExists(atPath: fileURL.path) {
            return try Data(contentsOf: fileURL)
        }
        return try Self.encoder.encode(snapshot)
    }

    func previewImport(_ data: Data) throws -> WorkspaceLibraryImportPreview {
        let imported = try Self.decodedImport(data)
        return WorkspaceLibraryImportPreview(
            bookmarks: imported.bookmarks.count,
            recents: imported.recents.count,
            shortcuts: imported.shortcuts.count,
            workspaces: imported.workspaces.count
        )
    }

    /// Explicit import replaces the local library as one atomic transaction.
    /// The candidate is version-probed, fully decoded, and sanitized before the
    /// existing snapshot or file is touched.
    func importDataReplacingLibrary(_ data: Data) throws {
        let imported = try Self.decodedImport(data)
        let previousSnapshot = snapshot
        let previousWarning = loadWarning
        let previousReadOnly = isReadOnly
        let previousFutureVersion = decodedFutureVersion

        snapshot = imported
        loadWarning = nil
        isReadOnly = false
        decodedFutureVersion = nil
        do {
            try persist()
        } catch {
            snapshot = previousSnapshot
            loadWarning = previousWarning
            isReadOnly = previousReadOnly
            decodedFutureVersion = previousFutureVersion
            throw error
        }
    }

    private func mutate(_ body: (inout WorkspaceLibrarySnapshot) -> Void) throws {
        if isReadOnly {
            throw WorkspaceLibraryError.libraryRequiresNewerApp(
                foundVersion: decodedFutureVersion ?? WorkspaceLibrarySnapshot.currentVersion + 1,
                supportedVersion: WorkspaceLibrarySnapshot.currentVersion
            )
        }
        let previous = snapshot
        body(&snapshot)
        do {
            try persist()
        } catch {
            snapshot = previous
            throw error
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let probedVersion = try Self.decoder.decode(
                WorkspaceLibraryVersionProbe.self,
                from: data
            ).version
            if probedVersion > WorkspaceLibrarySnapshot.currentVersion {
                decodedFutureVersion = probedVersion
                isReadOnly = true
                loadWarning = WorkspaceLibraryError.libraryRequiresNewerApp(
                    foundVersion: probedVersion,
                    supportedVersion: WorkspaceLibrarySnapshot.currentVersion
                ).localizedDescription
                snapshot = WorkspaceLibrarySnapshot()
                return
            }
            let decoded = try Self.decoder.decode(WorkspaceLibrarySnapshot.self, from: data)
            snapshot = Self.sanitizedSnapshot(decoded)
        } catch {
            loadWarning = error.localizedDescription
            preserveCorruptFile()
            snapshot = WorkspaceLibrarySnapshot()
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func decodedImport(_ data: Data) throws -> WorkspaceLibrarySnapshot {
        do {
            let version = try decoder.decode(WorkspaceLibraryVersionProbe.self, from: data).version
            guard version <= WorkspaceLibrarySnapshot.currentVersion else {
                throw WorkspaceLibraryError.libraryRequiresNewerApp(
                    foundVersion: version,
                    supportedVersion: WorkspaceLibrarySnapshot.currentVersion
                )
            }
            return sanitizedSnapshot(try decoder.decode(WorkspaceLibrarySnapshot.self, from: data))
        } catch let error as WorkspaceLibraryError {
            throw error
        } catch {
            throw WorkspaceLibraryError.invalidImportFile(error.localizedDescription)
        }
    }

    private func preserveCorruptFile() {
        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.deletingPathExtension().lastPathComponent
        let destination = directory.appendingPathComponent("\(base)-corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func sanitizedSnapshot(_ source: WorkspaceLibrarySnapshot) -> WorkspaceLibrarySnapshot {
        var result = WorkspaceLibrarySnapshot()
        result.bookmarks = source.bookmarks.prefix(maximumBookmarks).compactMap { bookmark in
            guard let candidate = URL(string: bookmark.url),
                  let url = URLPersistenceSanitizer.sanitizedURL(candidate) else { return nil }
            return BrowserBookmark(
                id: bookmark.id,
                title: cleanTitle(bookmark.title, fallbackURL: url),
                url: normalizedURLString(url),
                createdAt: bookmark.createdAt,
                lastOpenedAt: bookmark.lastOpenedAt
            )
        }
        result.recents = source.recents.prefix(maximumRecents).compactMap { recent in
            guard let candidate = URL(string: recent.url),
                  let url = URLPersistenceSanitizer.sanitizedURL(candidate) else { return nil }
            return RecentDestination(
                id: recent.id,
                title: cleanTitle(recent.title, fallbackURL: url),
                url: normalizedURLString(url),
                visitedAt: recent.visitedAt
            )
        }
        var occupiedShortcutKeys = Set<String>()
        result.shortcuts = source.shortcuts.prefix(maximumShortcuts).compactMap { shortcut in
            let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let url = validatedShortcutURL(shortcut.url) else { return nil }

            var localKeys = Set<String>()
            let aliases = shortcut.aliases.prefix(maximumAliasesPerShortcut).compactMap { raw -> String? in
                let alias = String(
                    raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
                )
                let key = SmartAddressResolver.normalizedShortcutKey(alias)
                guard !alias.isEmpty,
                      !key.isEmpty,
                      !occupiedShortcutKeys.contains(key),
                      localKeys.insert(key).inserted else { return nil }
                return String(alias.prefix(40))
            }
            guard !aliases.isEmpty else { return nil }
            occupiedShortcutKeys.formUnion(localKeys)
            return AddressShortcut(
                id: shortcut.id,
                name: String(name.prefix(80)),
                aliases: aliases,
                url: normalizedURLString(url),
                createdAt: shortcut.createdAt,
                updatedAt: shortcut.updatedAt
            )
        }
        result.workspaces = source.workspaces.prefix(maximumWorkspaces).compactMap { workspace in
            let name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let panels = workspace.panels.prefix(maximumPanelsPerWorkspace).compactMap(sanitizedPanel)
            guard !name.isEmpty, !panels.isEmpty else { return nil }
            return SavedWorkspace(
                id: workspace.id,
                name: name,
                createdAt: workspace.createdAt,
                updatedAt: workspace.updatedAt,
                panels: panels
            )
        }
        return result
    }

    private static func sanitizedPanel(_ panel: WorkspacePanelSnapshot) -> WorkspacePanelSnapshot? {
        guard panel.x.isFinite, panel.y.isFinite,
              panel.width.isFinite, panel.height.isFinite,
              panel.opacity.isFinite else { return nil }
        var result = panel
        result.width = min(max(panel.width, 260), 10_000)
        result.height = min(max(panel.height, 180), 10_000)
        result.opacity = min(max(panel.opacity, 0.2), 1)
        result.edgeAutoHideEnabled = panel.edgeAutoHideEnabled ?? false

        switch panel.panelKind {
        case .web:
            guard let primaryCandidate = URL(string: panel.url),
                  let url = URLPersistenceSanitizer.sanitizedURL(primaryCandidate) else { return nil }
            let validTabURLs = panel.savedTabURLStrings
                .prefix(maximumTabsPerPanel)
                .compactMap { value -> String? in
                    guard let candidate = URL(string: value),
                          let sanitizedURL = URLPersistenceSanitizer.sanitizedURL(candidate) else {
                        return nil
                    }
                    return normalizedURLString(sanitizedURL)
                }
            let normalizedPrimary = validTabURLs.first ?? normalizedURLString(url)
            result.kind = .web
            result.url = normalizedPrimary
            result.tabURLs = validTabURLs.isEmpty ? [normalizedPrimary] : validTabURLs
            result.selectedTabIndex = min(
                max(panel.selectedTabIndex ?? 0, 0),
                max((result.tabURLs?.count ?? 1) - 1, 0)
            )
            return result
        case .legacyMirror:
            // The raw case remains decodable so one retired panel cannot make
            // the whole library look corrupt. It is intentionally not retained.
            return nil
        }
    }

    static func isPersistableWebURL(_ url: URL) -> Bool {
        URLPersistenceSanitizer.sanitizedURL(url) != nil
    }

    private static func validatedShortcutURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://"),
              let url = SmartAddressResolver.resolve(trimmed),
              let sanitizedURL = URLPersistenceSanitizer.sanitizedURL(url) else { return nil }
        return sanitizedURL
    }

    private static func normalizedURLString(_ url: URL) -> String {
        url.absoluteString
    }

    private static func URLsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive]) == .orderedSame
    }

    private static func cleanTitle(_ title: String, fallbackURL: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(160)) }
        return fallbackURL.host?.replacingOccurrences(of: "www.", with: "") ?? fallbackURL.absoluteString
    }
}

enum WorkspaceLibrarySelfTest {
    static func run() -> String? {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CornerFloat-Library-SelfTest-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("Library.json")
        defer { try? fileManager.removeItem(at: root) }

        do {
            let store = WorkspaceLibraryStore(fileURL: file)
            let fixed = Date(timeIntervalSince1970: 1_700_000_000)
            let google = URL(string: "https://www.google.com/")!
            let chatGPT = URL(string: "https://chatgpt.com/auth/login")!

            let privacyFile = root.appendingPathComponent("Privacy-Library.json")
            let privacyStore = WorkspaceLibraryStore(fileURL: privacyFile)
            let authenticationURL = URL(
                string: "https://user:password@example.com/callback?code=secret&STATE=secret&q=kept#access_token=secret"
            )!
            let expectedPersistedURL = "https://example.com/callback?q=kept"
            try privacyStore.recordRecent(
                title: "Authentication callback",
                url: authenticationURL,
                now: fixed
            )
            let privacyBookmark = try privacyStore.addBookmark(
                title: "Authentication callback",
                url: authenticationURL,
                now: fixed
            )
            let privacyPanel = WorkspacePanelSnapshot(
                url: authenticationURL.absoluteString,
                tabURLs: [authenticationURL.absoluteString, google.absoluteString],
                selectedTabIndex: 0,
                frame: CGRect(x: 20, y: 20, width: 400, height: 600),
                isVisible: true,
                opacity: 1,
                isClickThrough: false
            )
            let privacyWorkspace = try privacyStore.saveWorkspace(
                name: "Private callback",
                panels: [privacyPanel],
                now: fixed
            )
            let persistedPrivacyText = String(
                decoding: try Data(contentsOf: privacyFile),
                as: UTF8.self
            )
            let lowercasedPrivacyText = persistedPrivacyText.lowercased()
            guard privacyStore.snapshot.recents.first?.url == expectedPersistedURL,
                  privacyBookmark.url == expectedPersistedURL,
                  privacyWorkspace.panels.first?.url == expectedPersistedURL,
                  privacyWorkspace.panels.first?.savedTabURLStrings == [
                      expectedPersistedURL,
                      google.absoluteString
                  ],
                  persistedPrivacyText.contains("q=kept"),
                  !lowercasedPrivacyText.contains("password"),
                  !lowercasedPrivacyText.contains("code=secret"),
                  !lowercasedPrivacyText.contains("state=secret"),
                  !lowercasedPrivacyText.contains("access_token") else {
                return "authentication data crossed a library persistence boundary"
            }

            try store.recordRecent(title: "Google", url: google, now: fixed)
            try store.recordRecent(title: "ChatGPT", url: chatGPT, now: fixed.addingTimeInterval(1))
            try store.recordRecent(title: "Google Search", url: google, now: fixed.addingTimeInterval(2))
            guard store.snapshot.recents.map(\.url) == [google.absoluteString, chatGPT.absoluteString],
                  store.snapshot.recents.first?.title == "Google Search" else {
                return "recent destinations were not de-duplicated in latest-first order"
            }

            let firstBookmark = try store.addBookmark(title: "Google", url: google, now: fixed)
            let updatedBookmark = try store.addBookmark(title: "Google Home", url: google, now: fixed.addingTimeInterval(3))
            guard firstBookmark.id == updatedBookmark.id,
                  store.snapshot.bookmarks.count == 1,
                  store.snapshot.bookmarks.first?.title == "Google Home" else {
                return "bookmark upsert did not preserve identity"
            }

            let shortcut = try store.saveShortcut(
                name: "University Mail",
                aliases: ["UniMail", "uni mail", "UniMail"],
                urlString: "https://mail.google.com/",
                now: fixed
            )
            guard shortcut.aliases == ["UniMail"],
                  SmartAddressResolver.resolve(
                    "uni mail",
                    customShortcuts: store.snapshot.shortcuts
                  ) == URL(string: "https://mail.google.com/") else {
                return "custom shortcut was not normalized and resolved"
            }
            do {
                _ = try store.saveShortcut(
                    name: "Conflicting Alias",
                    aliases: ["UNIMAIL"],
                    urlString: "https://example.com/",
                    now: fixed
                )
                return "duplicate custom shortcut alias was accepted"
            } catch WorkspaceLibraryError.duplicateShortcutAlias {
                // Expected.
            }

            let panel = WorkspacePanelSnapshot(
                url: chatGPT.absoluteString,
                tabURLs: [chatGPT.absoluteString, google.absoluteString],
                selectedTabIndex: 1,
                frame: CGRect(x: 900, y: 80, width: 420, height: 640),
                isVisible: true,
                opacity: 0.85,
                isClickThrough: false,
                edgeAutoHideEnabled: true
            )
            let workspace = try store.saveWorkspace(name: "Study", panels: [panel], now: fixed)
            let updated = try store.saveWorkspace(name: "study", panels: [panel], now: fixed.addingTimeInterval(4))
            guard workspace.id == updated.id,
                  store.snapshot.workspaces.count == 1,
                  store.snapshot.workspaces.first?.panels.count == 1 else {
                return "workspace upsert did not replace a same-name workspace"
            }

            let reloaded = WorkspaceLibraryStore(fileURL: file)
            guard reloaded.snapshot == store.snapshot,
                  reloaded.snapshot.workspaces.first?.panels.first?.savedTabURLStrings.count == 2,
                  reloaded.snapshot.workspaces.first?.panels.first?.selectedTabIndex == 1,
                  reloaded.snapshot.workspaces.first?.panels.first?.edgeAutoHideEnabled == true else {
                return "persisted library did not round-trip"
            }

            let importFile = root.appendingPathComponent("Imported-Library.json")
            let importStore = WorkspaceLibraryStore(fileURL: importFile)
            let exportData = try store.exportData()
            let preview = try importStore.previewImport(exportData)
            guard preview == WorkspaceLibraryImportPreview(
                bookmarks: 1,
                recents: 2,
                shortcuts: 1,
                workspaces: 1
            ) else {
                return "library import preview did not describe the sanitized payload"
            }
            try importStore.importDataReplacingLibrary(exportData)
            guard importStore.snapshot == store.snapshot else {
                return "exported library did not import as an equivalent snapshot"
            }
            let bytesBeforeRejectedImport = try Data(contentsOf: importFile)
            let snapshotBeforeRejectedImport = importStore.snapshot
            do {
                try importStore.importDataReplacingLibrary(Data("not-json".utf8))
                return "malformed library import was accepted"
            } catch WorkspaceLibraryError.invalidImportFile(_) {
                guard importStore.snapshot == snapshotBeforeRejectedImport,
                      try Data(contentsOf: importFile) == bytesBeforeRejectedImport else {
                    return "rejected malformed import modified the current library"
                }
            }

            var futureImport = WorkspaceLibrarySnapshot()
            futureImport.version = WorkspaceLibrarySnapshot.currentVersion + 1
            let futureImportEncoder = JSONEncoder()
            futureImportEncoder.dateEncodingStrategy = .iso8601
            let futureImportData = try futureImportEncoder.encode(futureImport)
            do {
                try importStore.importDataReplacingLibrary(futureImportData)
                return "future library import was accepted"
            } catch WorkspaceLibraryError.libraryRequiresNewerApp(_, _) {
                guard importStore.snapshot == snapshotBeforeRejectedImport,
                      try Data(contentsOf: importFile) == bytesBeforeRejectedImport else {
                    return "rejected future import modified the current library"
                }
            }
            guard case let .some(.web(tabURLs, selectedIndex)) = panel.restoreContent,
                  tabURLs == [chatGPT, google], selectedIndex == 1 else {
                return "web restore policy did not preserve tabs and selection"
            }

            let currentData = try Data(contentsOf: file)
            guard let currentRoot = try JSONSerialization.jsonObject(with: currentData) as? [String: Any],
                  let currentWorkspaces = currentRoot["workspaces"] as? [[String: Any]],
                  var mixedWorkspace = currentWorkspaces.first,
                  let currentPanels = mixedWorkspace["panels"] as? [[String: Any]],
                  let legacyWebPanel = currentPanels.first else {
                return "could not prepare legacy workspace compatibility fixture"
            }

            var legacyMirrorPanel = legacyWebPanel
            legacyMirrorPanel["kind"] = "mirrorPlaceholder"
            legacyMirrorPanel["url"] = ""
            legacyMirrorPanel.removeValue(forKey: "tabURLs")
            legacyMirrorPanel.removeValue(forKey: "selectedTabIndex")
            legacyMirrorPanel["mirrorSourceApplicationName"] = "Preview"
            legacyMirrorPanel["mirrorSourceWindowTitle"] = "Project Notes.pdf"
            mixedWorkspace["panels"] = [legacyWebPanel, legacyMirrorPanel]

            var mirrorOnlyWorkspace = mixedWorkspace
            mirrorOnlyWorkspace["id"] = UUID().uuidString
            mirrorOnlyWorkspace["name"] = "Legacy Mirror Only"
            mirrorOnlyWorkspace["panels"] = [legacyMirrorPanel]

            var versionFourRoot = currentRoot
            versionFourRoot["version"] = 4
            versionFourRoot["workspaces"] = [mixedWorkspace, mirrorOnlyWorkspace]
            let versionFourData = try JSONSerialization.data(
                withJSONObject: versionFourRoot,
                options: [.sortedKeys]
            )
            try versionFourData.write(to: file, options: .atomic)

            let versionFourStore = WorkspaceLibraryStore(fileURL: file)
            let corruptFilesAfterVersionFourLoad = try fileManager.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains("-corrupt-") }
            guard !versionFourStore.isReadOnly,
                  versionFourStore.loadWarning == nil,
                  corruptFilesAfterVersionFourLoad.isEmpty,
                  versionFourStore.snapshot.bookmarks.count == 1,
                  versionFourStore.snapshot.recents.count == 2,
                  versionFourStore.snapshot.shortcuts.count == 1,
                  versionFourStore.snapshot.workspaces.count == 1,
                  versionFourStore.snapshot.workspaces.first?.panels.count == 1,
                  versionFourStore.snapshot.workspaces.first?.panels.first?.panelKind == .web else {
                return "version 4 legacy mirrors were not ignored without damaging library data"
            }

            try versionFourStore.recordRecent(
                title: "Google after migration",
                url: google,
                now: fixed.addingTimeInterval(5)
            )
            let cleanedData = try Data(contentsOf: file)
            let cleanedText = String(decoding: cleanedData, as: UTF8.self)
            guard !cleanedText.contains("mirrorPlaceholder"),
                  !cleanedText.contains("mirrorSourceApplicationName"),
                  !cleanedText.contains("mirrorSourceWindowTitle") else {
                return "a normal mutation did not purge retired mirror fields"
            }
            let cleanedStore = WorkspaceLibraryStore(fileURL: file)
            guard cleanedStore.loadWarning == nil,
                  cleanedStore.snapshot.workspaces.count == 1,
                  cleanedStore.snapshot.workspaces.first?.panels.count == 1 else {
                return "cleaned version 4 library did not reload"
            }

            var versionThreeRoot = versionFourRoot
            versionThreeRoot["version"] = 3
            versionThreeRoot.removeValue(forKey: "shortcuts")
            let versionThreeData = try JSONSerialization.data(
                withJSONObject: versionThreeRoot,
                options: [.sortedKeys]
            )
            try versionThreeData.write(to: file, options: .atomic)
            let versionThreeStore = WorkspaceLibraryStore(fileURL: file)
            guard !versionThreeStore.isReadOnly,
                  versionThreeStore.loadWarning == nil,
                  versionThreeStore.snapshot.bookmarks.count == 1,
                  versionThreeStore.snapshot.recents.count == 2,
                  versionThreeStore.snapshot.workspaces.count == 1,
                  versionThreeStore.snapshot.workspaces.first?.panels.count == 1,
                  versionThreeStore.snapshot.workspaces.first?.panels.first?.panelKind == .web else {
                return "version 3 legacy mirrors were not ignored safely"
            }

            for legacyVersion in [1, 2] {
                var legacyRoot = currentRoot
                legacyRoot["version"] = legacyVersion
                legacyRoot.removeValue(forKey: "shortcuts")
                var legacyWorkspaces = currentWorkspaces
                var legacyWorkspace = legacyWorkspaces[0]
                var versionedWebPanel = legacyWebPanel
                versionedWebPanel.removeValue(forKey: "kind")
                versionedWebPanel.removeValue(forKey: "tabURLs")
                versionedWebPanel.removeValue(forKey: "selectedTabIndex")
                versionedWebPanel.removeValue(forKey: "edgeAutoHideEnabled")
                legacyWorkspace["panels"] = [versionedWebPanel]
                legacyWorkspaces[0] = legacyWorkspace
                legacyRoot["workspaces"] = legacyWorkspaces
                let legacyData = try JSONSerialization.data(
                    withJSONObject: legacyRoot,
                    options: [.sortedKeys]
                )
                try legacyData.write(to: file, options: .atomic)
                let legacyStore = WorkspaceLibraryStore(fileURL: file)
                guard !legacyStore.isReadOnly,
                      legacyStore.loadWarning == nil,
                      legacyStore.snapshot.version == WorkspaceLibrarySnapshot.currentVersion,
                      legacyStore.snapshot.workspaces.first?.panels.count == 1,
                      legacyStore.snapshot.workspaces.first?.panels.first?.panelKind == .web else {
                    return "version \(legacyVersion) web-only workspace was not migrated safely"
                }
            }

            try Data("not-json".utf8).write(to: file, options: .atomic)
            let recovered = WorkspaceLibraryStore(fileURL: file)
            guard recovered.snapshot == WorkspaceLibrarySnapshot(), recovered.loadWarning != nil else {
                return "corrupt library was not recovered safely"
            }

            var futureSnapshot = WorkspaceLibrarySnapshot()
            futureSnapshot.version = WorkspaceLibrarySnapshot.currentVersion + 1
            futureSnapshot.recents = [
                RecentDestination(
                    id: UUID(),
                    title: "Future data",
                    url: google.absoluteString,
                    visitedAt: fixed
                )
            ]
            let futureEncoder = JSONEncoder()
            futureEncoder.dateEncodingStrategy = .iso8601
            let futureData = try futureEncoder.encode(futureSnapshot)
            try futureData.write(to: file, options: .atomic)
            let futureStore = WorkspaceLibraryStore(fileURL: file)
            guard futureStore.isReadOnly,
                  futureStore.loadWarning != nil,
                  try Data(contentsOf: file) == futureData else {
                return "future library schema was not preserved as read-only"
            }
            do {
                try futureStore.recordRecent(title: "Must not overwrite", url: chatGPT, now: fixed)
                return "future library schema allowed a destructive write"
            } catch WorkspaceLibraryError.libraryRequiresNewerApp(_, _) {
                guard try Data(contentsOf: file) == futureData else {
                    return "future library changed after a blocked write"
                }
            }

            var incompatibleFutureRoot = currentRoot
            incompatibleFutureRoot["version"] = WorkspaceLibrarySnapshot.currentVersion + 1
            var incompatibleWorkspace = mixedWorkspace
            var incompatiblePanel = legacyWebPanel
            incompatiblePanel["kind"] = "futurePanelType"
            incompatiblePanel["futureConfiguration"] = ["mode": "unknown-to-this-build"]
            incompatibleWorkspace["panels"] = [incompatiblePanel]
            incompatibleFutureRoot["workspaces"] = [incompatibleWorkspace]
            let incompatibleFutureData = try JSONSerialization.data(
                withJSONObject: incompatibleFutureRoot,
                options: [.sortedKeys]
            )
            let corruptCountBeforeFutureProbe = try fileManager.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains("-corrupt-") }
                .count
            try incompatibleFutureData.write(to: file, options: .atomic)

            let incompatibleFutureStore = WorkspaceLibraryStore(fileURL: file)
            let corruptCountAfterFutureProbe = try fileManager.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains("-corrupt-") }
                .count
            guard incompatibleFutureStore.isReadOnly,
                  incompatibleFutureStore.loadWarning != nil,
                  corruptCountAfterFutureProbe == corruptCountBeforeFutureProbe,
                  try Data(contentsOf: file) == incompatibleFutureData else {
                return "an incompatible future payload was mistaken for a corrupt library"
            }
            do {
                try incompatibleFutureStore.recordRecent(
                    title: "Must stay read-only",
                    url: google,
                    now: fixed
                )
                return "an incompatible future payload allowed a destructive write"
            } catch WorkspaceLibraryError.libraryRequiresNewerApp(_, _) {
                guard try Data(contentsOf: file) == incompatibleFutureData else {
                    return "an incompatible future library changed after a blocked write"
                }
            }
        } catch {
            return error.localizedDescription
        }

        return nil
    }
}
