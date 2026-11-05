import AppKit
import HanareCore

/// Access to the two menu bar files macOS protects, granted by the user picking each one in an
/// open panel. The panel runs outside Hanare, so a file chosen there can be read and written
/// without Full Disk Access. The grant is kept as a bookmark across launches.
@MainActor
enum ProtectedFileAccess {
    struct File {
        let container: URL
        let domain: String
        let bookmarkKey: String

        var url: URL { container.appending(path: "Library/Preferences/\(domain).plist") }
        var isReadable: Bool { NSDictionary(contentsOf: url) != nil }
    }

    /// Control Center's list of apps allowed in the menu bar: hiding app icons.
    static let appList = File(
        container: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.com.apple.controlcenter"),
        domain: "group.com.apple.controlcenter",
        bookmarkKey: "accessBookmark.appList"
    )
    /// The menu bar order: moving icons without the pointer.
    static let menuBarOrder = File(
        container: MenuBarPositionStore.containerURL,
        domain: MenuBarPositionStore.domain,
        bookmarkKey: "accessBookmark.menuBarOrder"
    )
    static let all = [appList, menuBarOrder]

    static var hasAccess: Bool { all.allSatisfy(\.isReadable) }

    private static var scopedURLs: [URL] = []

    /// Takes up the grants kept from earlier launches.
    static func activate() {
        for file in all {
            guard let data = UserDefaults.standard.data(forKey: file.bookmarkKey) else { continue }
            var isStale = false
            guard let url = (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &isStale))
                ?? (try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)) else { continue }
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
            if isStale { store(url, for: file) }
        }
    }

    /// Explains what is needed and shows an open panel for each file that is not readable yet.
    /// Returns whether every file is readable afterwards.
    @discardableResult
    static func request() -> Bool {
        let missing = all.filter { !$0.isReadable }
        guard !missing.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.accessTitle
        alert.informativeText = L10n.accessMessage
        alert.addButton(withTitle: L10n.allowAccessEllipsis)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        for file in missing where !pick(file) { break }
        return hasAccess
    }

    private static func pick(_ file: File) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Pointing the panel at the file itself opens its folder with the file already selected,
        // so the user only has to confirm.
        panel.directoryURL = file.url
        panel.message = L10n.choosePanelMessage(file.url.lastPathComponent)
        panel.prompt = L10n.allowAccess
        NSApp.activate()
        guard panel.runModal() == .OK, let picked = panel.url,
              picked.standardizedFileURL.path == file.url.standardizedFileURL.path else { return false }
        store(picked, for: file)
        if picked.startAccessingSecurityScopedResource() { scopedURLs.append(picked) }
        return file.isReadable
    }

    private static func store(_ url: URL, for file: File) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope])) ?? (try? url.bookmarkData())
        if let data { UserDefaults.standard.set(data, forKey: file.bookmarkKey) }
    }
}
