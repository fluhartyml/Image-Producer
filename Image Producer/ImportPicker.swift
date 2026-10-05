//
//  ImportPicker.swift
//  Image Producer
//
//  NEW FROM IMPORT ON THE iPAD — 2026-10-05. Michael: "image producer should be able to
//  open any supported file format." The iPad's launch browser only lists Image Producer
//  projects (every PSD, PDF and picture is greyed out there), so the launch screen gets
//  the Mac's "New from Import…" too.
//
//  The launch screen's NewDocumentButton asks for a file URL asynchronously; this presents
//  the Files picker and waits for the choice. The picker takes a COPY (asCopy: true), so
//  the user's original file is never opened for writing — the same promise the Mac makes.
//

#if !os(macOS) && canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

@MainActor
enum ImportPicker {
    /// Present the Files picker for `types` and return a copy of the chosen file, or nil
    /// if the user cancels.
    static func pick(types: [UTType]) async -> URL? {
        // Diagnostics for build 271 — his tap on 270 went straight to a blank document.
        // print() reaches `devicectl … --console`; remove once the cause is known.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        print("IP-IMPORT: scenes=\(scenes.count) states=\(scenes.map { $0.activationState.rawValue }) windows=\(scenes.flatMap(\.windows).count)")
        guard let top = topViewController() else {
            print("IP-IMPORT: no view controller to present on")
            return nil
        }
        print("IP-IMPORT: presenting on \(type(of: top)) inWindow=\(top.viewIfLoaded?.window != nil) beingDismissed=\(top.isBeingDismissed)")
        return await withCheckedContinuation { continuation in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = Delegate { url in
                print("IP-IMPORT: picker returned \(url?.lastPathComponent ?? "nil (cancelled)")")
                current = nil
                continuation.resume(returning: url)
            }
            current = delegate              // the picker holds its delegate weakly
            picker.delegate = delegate
            picker.allowsMultipleSelection = false
            top.present(picker, animated: true) {
                print("IP-IMPORT: picker on screen=\(picker.viewIfLoaded?.window != nil)")
            }
        }
    }

    private static var current: Delegate?

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        private var finish: ((URL?) -> Void)?
        init(_ finish: @escaping (URL?) -> Void) { self.finish = finish }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish?(urls.first); finish = nil
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish?(nil); finish = nil
        }
    }
}
#endif
