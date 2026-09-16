//
//  DesktopAccess.swift
//  Image Producer
//
//  The sandbox does not let an app write to the Desktop. The user grants it by choosing the
//  folder once in an open panel; the grant is kept as a security-scoped bookmark so it is
//  never asked again. Added 2026-09-16 when Save to Desktop failed with "You don't have
//  permission to save the file … in the folder Desktop."
//

#if os(macOS)
import AppKit

enum DesktopAccess {
    private static let bookmarkKey = "ImageProducer.desktopBookmark"

    /// The real Desktop — the user's home, not the sandbox container's.
    static var realDesktop: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
    }

    /// A Desktop URL this app may write to: the remembered grant, or — the first time — the
    /// user choosing it. `nil` if they cancel or pick some other folder.
    static func grantedDesktop() -> URL? {
        if let url = resolveBookmark() { return url }
        return askForDesktop()
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
        if stale { remember(url) }
        return url
    }

    private static func askForDesktop() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = realDesktop.deletingLastPathComponent()
        panel.message = "Choose your Desktop folder so Image Producer can save there. You will only be asked once."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        // Only the Desktop. Saving somewhere else under a button named "Save to Desktop"
        // would put his file where he will not look for it.
        guard chosen.resolvingSymlinksInPath().standardizedFileURL.path
                == realDesktop.resolvingSymlinksInPath().standardizedFileURL.path else { return nil }
        remember(chosen)
        return chosen
    }

    private static func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}
#endif
