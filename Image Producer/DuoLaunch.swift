//
//  DuoLaunch.swift
//  Image Producer
//
//  REM: OUR OWN LAUNCH SCREEN ON THE iPHONE DUO — the Mockup, 2026-11-05
//  (~/Desktop/Image-Producer-Duo-Launch-Mockup-DRAFT-2026-11-05.html, lines 001–027, all LOCKED).
//  His words: "wasted space is not optomized for iphone dou" · "build it for the duo only".
//
//  WHY A PAGE ON TOP, NOT A REPLACEMENT (line 022, proven on a scratch copy 12:13–12:27):
//  · On iPhone, SwiftUI gives our code no way to open a document (`openDocument` is
//    unavailable on iOS). Only Apple's launch screen can open one, through its file browser.
//  · Rename borrows that same browser (CanvasInspector.browserRename → documentBrowser()).
//  · A layer drawn in Apple's overlay covers the screen but taps go THROUGH it to Apple's.
//  · A full-screen page PRESENTED over Apple's launch screen takes taps, and handing a file
//    to Apple's browser (its delegate's didPickDocumentsAt) opens it in the editor; rename
//    still works afterwards. So Apple's screen stays alive underneath and does the opening;
//    this page only replaces what you see.
//
//  Layout = his relationships (lines 010–015; sizes are suggestions, relationships are the rule):
//  title near the top · New Image + New from Import on one row, each sized to its words ·
//  the card's top edge just under that row, its bottom at the bottom, growing to fill ·
//  search + top bar (List, Select, Connect to Server — no "…") ride the card's top edge ·
//  tabs Recents / Shared / Browse at the card's bottom right.
//  Duo only (020), closed AND opened (001). Every other device keeps Apple's screen.
//

#if os(iOS)
import SwiftUI
import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Showing and opening

@MainActor
enum DuoLaunch {
    /// REM: THE DUO, BY MODEL. iPhone19,4 is the iPhone Duo simulator's model identifier
    /// (simctl, 2026-11-05). ⚠️ Not yet checked against a real Duo — if a real one reports a
    /// different identifier, add it here.
    static let duoModels: Set<String> = ["iPhone19,4"]

    static let isDuo: Bool = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return duoModels.contains(sim)
        }
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return duoModels.contains(model)
    }()

    private static weak var page: UIViewController?
    private static var openEditors = 0
    private static var opening = false

    /// REM: The fix found in the 022 test — the page came back over the editor right after a
    /// file opened. So the page shows only when no editor is open and no open is in flight.
    static func editorAppeared() {
        ipLog("DuoLaunch editorAppeared")
        openEditors += 1
        opening = false
    }
    static func editorDisappeared() {
        openEditors = max(0, openEditors - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showIfNeeded() }
    }

    /// Put our page over Apple's launch screen when it is showing with no file open.
    static func showIfNeeded() {
        guard isDuo, !ProcessInfo.processInfo.arguments.contains("-DuoNoPage"), page == nil, !opening, openEditors == 0,
              let host = launchHost(), host.presentedViewController == nil else { return }
        let vc = UIHostingController(rootView: DuoLaunchPage())
        vc.modalPresentationStyle = .fullScreen
        page = vc
        host.present(vc, animated: false)
    }

    /// Open `url` the way Apple's own launch screen does: hand it to Apple's file browser.
    static func open(_ url: URL) {
        guard let browser = CanvasInspector.documentBrowser(), let delegate = browser.delegate else {
            ipLog("DuoLaunch open: Apple's file browser was not found")
            return
        }
        // REM: ORDER (13:2x–13:4x runs): with our page still on top, Apple makes the document but
        // never shows the editor. So our page goes first, then Apple opens the file.
        opening = true
        let hand = {
            delegate.documentBrowser?(browser, didPickDocumentsAt: [url])
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { opening = false; showIfNeeded() }
        }
        if let page { page.dismiss(animated: false, completion: hand); self.page = nil } else { hand() }
    }

    /// TEMP diagnostics (13:3x): what covers the editor after an open.
    static func dumpViews() {
        func walk(_ v: UIView, _ d: Int) {
            guard d < 9 else { return }
            if v.frame.width > 300 && !v.isHidden && v.alpha > 0.01 {
                ipLog("DUOVIEW " + String(repeating: " ", count: d) + "\(type(of: v)) \(v.frame) a=\(v.alpha) bg=\(String(describing: v.backgroundColor))")
            }
            for sub in v.subviews { walk(sub, d + 1) }
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows { ipLog("DUOVIEW window \(type(of: w)) level=\(w.windowLevel.rawValue) hidden=\(w.isHidden)"); walk(w, 1) }
        }
        func vcs(_ vc: UIViewController?, _ d: Int) {
            guard let vc else { return }
            ipLog("DUOVC " + String(repeating: " ", count: d) + "\(type(of: vc))")
            for c in vc.children { vcs(c, d + 1) }
            if let p = vc.presentedViewController { ipLog("DUOVC " + String(repeating: " ", count: d) + " presents:"); vcs(p, d + 2) }
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows { vcs(w.rootViewController, 1) }
        }
    }

    /// Apple's launch screen: the document view controller that holds no document.
    private static func launchHost() -> UIViewController? {
        func search(_ vc: UIViewController?) -> UIViewController? {
            guard let vc else { return nil }
            if let dvc = vc as? UIDocumentViewController, dvc.document == nil,
               dvc.viewIfLoaded?.window != nil { return dvc }
            for child in vc.children { if let hit = search(child) { return hit } }
            return nil
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { if let hit = search(window.rootViewController) { return hit } }
        }
        return nil
    }

    /// The top view controller, for presenting Apple's pickers from our page.
    static func topViewController() -> UIViewController? {
        var top = page
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

// MARK: - The files

struct DuoFile: Identifiable, Hashable {
    let url: URL
    let name: String
    let modified: Date
    var id: URL { url }
}

@MainActor @Observable
final class DuoFileStore {
    var recents: [DuoFile] = []
    var shared: [DuoFile] = []
    var thumbnails: [URL: UIImage] = [:]
    private var sharedQuery: NSMetadataQuery?

    /// Line 023: Image Producer's own folder (iCloud Drive, or On My iPhone), newest first.
    func reload() {
        Task {
            let found = await Task.detached { () -> [DuoFile] in
                guard let dir = ImageDocument.projectsDirectory() else { return [] }
                let fm = FileManager.default
                let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [])) ?? []
                var files: [DuoFile] = []
                for item in items {
                    var url = item
                    var name = item.lastPathComponent
                    // A file still in iCloud only shows as ".Name.imgprd.icloud" until it downloads.
                    if name.hasPrefix("."), name.hasSuffix(".icloud") {
                        name = String(name.dropFirst().dropLast(".icloud".count))
                        url = dir.appendingPathComponent(name)
                    } else if name.hasPrefix(".") { continue }
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard ext == ImageDocument.projectExtension || ext == "psd" else { continue }
                    let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    files.append(DuoFile(url: url, name: (name as NSString).deletingPathExtension, modified: date))
                }
                return files.sorted { $0.modified > $1.modified }
            }.value
            recents = found
            for f in found where thumbnails[f.url] == nil { loadThumbnail(f.url) }
        }
    }

    /// Line 002: images shared with you over iCloud, like Apple's Shared tab.
    func startShared() {
        guard sharedQuery == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == YES", NSMetadataUbiquitousItemIsSharedKey)
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collectShared() }
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collectShared() }
        }
        sharedQuery = q
        q.start()
    }

    private func collectShared() {
        guard let q = sharedQuery else { return }
        q.disableUpdates()
        var out: [DuoFile] = []
        for case let item as NSMetadataItem in q.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            out.append(DuoFile(url: url, name: url.deletingPathExtension().lastPathComponent, modified: date))
        }
        q.enableUpdates()
        shared = out.sorted { $0.modified > $1.modified }
        for f in shared where thumbnails[f.url] == nil { loadThumbnail(f.url) }
    }

    /// The real picture: the project's own QuickLook/Thumbnail.png (ProjectThumbnail.swift),
    /// or the system's thumbnail (PSD, or a project saved before thumbnails existed).
    private func loadThumbnail(_ url: URL) {
        let stored = url.appendingPathComponent(ProjectThumbnail.folder).appendingPathComponent(ProjectThumbnail.file)
        if let img = UIImage(contentsOfFile: stored.path) { thumbnails[url] = img; return }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 120),
                                               scale: UIScreen.main.scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.uiImage else { return }
            DispatchQueue.main.async { self.thumbnails[url] = img }
        }
    }

    /// Delete the chosen files (asked first on the page). Coordinated, so iCloud follows.
    func delete(_ urls: [URL]) {
        Task.detached {
            for url in urls {
                var err: NSError?
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &err) { u in
                    try? FileManager.default.removeItem(at: u)
                }
            }
            await MainActor.run { self.reload() }
        }
    }
}

// MARK: - The page

private enum DuoTab: String, CaseIterable { case recents = "Recents", shared = "Shared", browse = "Browse" }

struct DuoLaunchPage: View {
    @State private var store = DuoFileStore()
    @State private var search = ""
    @State private var asGrid = false
    @State private var selecting = false
    @State private var selection = Set<URL>()
    @State private var tab: DuoTab = .recents
    @State private var askDelete = false
    @State private var problem: String?

    private var shown: [DuoFile] {
        let all = tab == .shared ? store.shared : store.recents
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 10) {
            // 010: title near the top.
            Text(launchTitle)
                .scaledFont(26, weight: .bold)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 4)
                .accessibilityIdentifier("duo.title")
            // 011: both buttons on one row, each sized to its words.
            HStack(spacing: 10) {
                Button { newImage() } label: { Text("New Image").scaledFont(18, weight: .semibold) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("duo.newImage")
                Button { newFromImport() } label: { Text("New from Import").scaledFont(18, weight: .semibold) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Import")
                    .accessibilityIdentifier("duo.newFromImport")
            }
            .fixedSize()
            card   // 012: top edge just under the row, bottom at the bottom.
        }
        .padding(.horizontal, 10)
        .background(mint.ignoresSafeArea())
        .onAppear { store.reload(); store.startShared() }
        .alert("Couldn't do that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
        .confirmationDialog("Delete \(selection.count) image\(selection.count == 1 ? "" : "s")?",
                            isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(Array(selection)); selection.removeAll(); selecting = false
            }
        } message: { Text("This can't be undone.") }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            // 013: search + top bar ride the card's top edge. No "…" — every action is its own button.
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                        .scaledFont(18)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("duo.search")
                }
                Button { asGrid.toggle() } label: {
                    Image(systemName: asGrid ? "list.bullet" : "square.grid.2x2").scaledFont(18)
                }
                .accessibilityLabel("List")
                .accessibilityIdentifier("duo.list")
                Button { selecting.toggle(); selection.removeAll() } label: {
                    Text(selecting ? "Done" : "Select").scaledFont(18)
                }
                .accessibilityIdentifier("duo.select")
                Button { pickElsewhere() } label: { Image(systemName: "server.rack").scaledFont(18) }
                    .accessibilityLabel("Connect to Server")
                    .accessibilityIdentifier("duo.connect")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            if selecting { selectionBar }

            Divider()
            ScrollView {
                if shown.isEmpty {
                    Text(tab == .shared ? "No images are shared with you." :
                            search.isEmpty ? "No images yet. Tap New Image to start one." : "No images match.")
                        .scaledFont(18).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if asGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 14) {
                        ForEach(shown) { f in gridCell(f) }
                    }
                    .padding(12)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { f in row(f); Divider().padding(.leading, 82) }
                    }
                }
            }
            .refreshable { store.reload() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("duo.files")

            // 014: tabs at the card's bottom right.
            HStack(spacing: 18) {
                Spacer()
                tabButton(.recents, "clock")
                tabButton(.shared, "person.2")
                tabButton(.browse, "folder")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .ignoresSafeArea(edges: .bottom)
        .accessibilityElement(children: .contain)   // keeps the buttons inside it their own names
        .accessibilityIdentifier("duo.card")
    }

    private var selectionBar: some View {
        let urls = Array(selection)
        return HStack(spacing: 20) {
            ShareLink(items: urls) { Label("Share", systemImage: "square.and.arrow.up").scaledFont(18) }
                .disabled(urls.isEmpty)
            Button { moveSelection(urls) } label: { Label("Move", systemImage: "folder").scaledFont(18) }
                .disabled(urls.isEmpty)
            Button(role: .destructive) { askDelete = true } label: { Label("Delete", systemImage: "trash").scaledFont(18) }
                .disabled(urls.isEmpty)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private func tabButton(_ t: DuoTab, _ symbol: String) -> some View {
        Button {
            if t == .browse { pickElsewhere() } else { tab = t }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).scaledFont(18)
                Text(t.rawValue).scaledFont(13)   // REM: tab captions are below 18 pt, as Apple's tab bar draws them.
            }
            .foregroundStyle(tab == t ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(t.rawValue)
        .accessibilityIdentifier("duo.tab.\(t.rawValue)")
    }

    // MARK: Rows

    private func thumb(_ f: DuoFile, side: CGFloat) -> some View {
        Group {
            if let img = store.thumbnails[f.url] {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").resizable().scaledToFit().padding(side * 0.25).foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ f: DuoFile) -> some View {
        Button { tapped(f) } label: {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: selection.contains(f.url) ? "checkmark.circle.fill" : "circle").scaledFont(20)
                }
                thumb(f, side: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).scaledFont(18).lineLimit(1)
                    Text(f.modified, format: .dateTime.month().day().hour().minute())
                        .scaledFont(18).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.name)
        .accessibilityIdentifier("duo.file.\(f.name)")
    }

    private func gridCell(_ f: DuoFile) -> some View {
        Button { tapped(f) } label: {
            VStack(spacing: 6) {
                thumb(f, side: 110)
                    .overlay(alignment: .topTrailing) {
                        if selecting {
                            Image(systemName: selection.contains(f.url) ? "checkmark.circle.fill" : "circle")
                                .scaledFont(20).padding(4)
                        }
                    }
                Text(f.name).scaledFont(18).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.name)
        .accessibilityIdentifier("duo.file.\(f.name)")
    }

    // MARK: Actions

    private func tapped(_ f: DuoFile) {
        if selecting {
            if selection.contains(f.url) { selection.remove(f.url) } else { selection.insert(f.url) }
        } else {
            DuoLaunch.open(f.url)
        }
    }

    /// 025: New Image — the same numbered ImageProducerNNNN, written then opened (as the Mac's ⌘N).
    private func newImage() {
        Task {
            let url = await Task.detached { ImageDocument.nextProjectURL() }.value
            guard let url, ImageDocument.writeNewProject(at: url) else {
                problem = "A new image couldn't be made in your Image Producer folder."; return
            }
            DuoLaunch.open(url)
        }
    }

    /// 025: New from Import — PSD (with layers), PDF and pictures, from a COPY of the file, named
    /// after the source (his idea 10-05: "use the original psd file name just change the extention").
    private func newFromImport() {
        Task {
            guard let source = await ImportPicker.pick(types: ImageDocument.newFromImportContentTypes) else { return }
            let base = source.deletingPathExtension().lastPathComponent
            let url = await Task.detached { () -> URL? in
                guard let dir = ImageDocument.projectsDirectory() else { return nil }
                var name = base, n = 2
                func at(_ s: String) -> URL { dir.appendingPathComponent(s).appendingPathExtension(ImageDocument.projectExtension) }
                while FileManager.default.fileExists(atPath: at(name).path) { name = "\(base) \(n)"; n += 1 }
                return at(name)
            }.value
            guard let url, ImageDocument.writeNewProject(at: url, from: source) else {
                problem = "\(source.lastPathComponent) couldn't be imported."; return
            }
            DuoLaunch.open(url)
        }
    }

    /// 024: Connect to Server and Browse — Apple's file picker, for a server or any other place.
    private func pickElsewhere() {
        DuoPicker.present(DuoPicker.opening(ImageDocument.readableContentTypes)) { urls in
            if let url = urls.first { DuoLaunch.open(url) }
        }
    }

    /// 024: Select ▸ Move — Apple's picker moves the chosen files to the place you pick.
    private func moveSelection(_ urls: [URL]) {
        DuoPicker.present(UIDocumentPickerViewController(forExporting: urls, asCopy: false)) { _ in
            selection.removeAll(); selecting = false; store.reload()
        }
    }

    private var mint: some View {
        // Same calming mint as Apple's launch screen in this app (his call, 2026-10-05).
        LinearGradient(
            colors: [Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                        ? .systemBackground : UIColor(red: 0.925, green: 0.973, blue: 0.945, alpha: 1) }),
                     Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                        ? .secondarySystemBackground : UIColor(red: 0.875, green: 0.949, blue: 0.906, alpha: 1) })],
            startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Apple's file picker

@MainActor
private enum DuoPicker {
    private static var current: Delegate?

    static func opening(_ types: [UTType]) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        p.allowsMultipleSelection = false
        return p
    }

    static func present(_ picker: UIDocumentPickerViewController, done: @escaping ([URL]) -> Void) {
        guard let top = DuoLaunch.topViewController() else { return }
        let d = Delegate { urls in current = nil; done(urls) }
        current = d
        picker.delegate = d
        top.present(picker, animated: true)
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let done: ([URL]) -> Void
        init(_ done: @escaping ([URL]) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { }
    }
}
#endif
