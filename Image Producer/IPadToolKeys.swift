//
//  IPadToolKeys.swift
//  Image Producer
//
//  REM: A3 ON THE iPAD, his word 11-04: "build the a3 ipad keys next". The Mac's letters
//  (005a: one plain letter per tool, no ⌘, "because a switch user may need one key rather than
//  a spoken word") and 012a's arrow nudge, for an iPad with a hardware keyboard.
//
//  The Mac uses an NSEvent monitor; UIKit has none. So an invisible view in the editor HOLDS
//  keyboard focus whenever nothing else wants it, and reads keys in pressesBegan. It steps
//  aside exactly where the Mac's monitor does:
//  - a text box (any UITextInput) is being typed in — it never takes focus from one, so the
//    letters type as letters;
//  - the font list's type-to-jump has focus (ToolShortcuts.typeToJumpActive);
//  - a sheet is up (its Return/Escape buttons must keep working);
//  - ⌘ ⌥ or ⌃ is held (menu shortcuts pass up the chain untouched). Shift is allowed:
//    B and b both pick Paint Drop Bucket; Shift-arrow moves 10 px.
//  Everything it doesn't use goes to super, up the responder chain, as if it weren't there.
//  It takes no touches (hitTest returns nil), so the canvas and controls are unchanged.
//  A held arrow repeats (UIKit sends one press, so the repeat is ours), same as the Mac.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

struct IPadToolKeys: UIViewRepresentable {
    var onPick: (Tool) -> Void
    /// 012a: an arrow key (dx, dy, Shift held). Returns true when it was used.
    var onArrow: (Int, Int, Bool) -> Bool
    /// 014: Space paints at the pixel cursor. Returns true when it was used.
    var onPaint: () -> Bool = { false }

    func makeUIView(context: Context) -> CatcherView {
        let v = CatcherView(); v.onPick = onPick; v.onArrow = onArrow; v.onPaint = onPaint; return v
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onPick = onPick; view.onArrow = onArrow; view.onPaint = onPaint
        // The editor changed (a tool tapped, a sheet closed…): take focus back if it's free.
        view.reclaimSoon()
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) { view.shutDown() }

    final class CatcherView: UIView {
        var onPick: (Tool) -> Void = { _ in }
        var onArrow: (Int, Int, Bool) -> Bool = { _, _, _ in false }
        var onPaint: () -> Bool = { false }
        /// Keys whose press began here; their end must not go to super alone.
        private var held: Set<UIKeyboardHIDUsage> = []
        private var repeatTask: Task<Void, Never>?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            let nc = NotificationCenter.default
            for name in [UITextField.textDidEndEditingNotification,
                         UITextView.textDidEndEditingNotification,
                         UIWindow.didBecomeKeyNotification] {
                nc.addObserver(self, selector: #selector(somethingLetGo), name: name, object: nil)
            }
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var canBecomeFirstResponder: Bool { true }

        /// Never takes a touch: taps go to whatever is underneath, as before.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stopRepeat() } else { reclaimSoon() }
        }

        @objc private func somethingLetGo() { reclaimSoon() }

        func reclaimSoon() {
            DispatchQueue.main.async { [weak self] in self?.reclaim() }
        }

        func shutDown() {
            stopRepeat()
            NotificationCenter.default.removeObserver(self)
            if isFirstResponder { resignFirstResponder() }
        }

        private var sheetIsUp: Bool { window?.rootViewController?.presentedViewController != nil }

        private func reclaim() {
            guard let window, window.isKeyWindow else { return }
            if sheetIsUp || ToolShortcuts.typeToJumpActive {
                if isFirstResponder { resignFirstResponder() }
                return
            }
            if isFirstResponder { return }
            // Never take focus from a text box being typed in.
            if FirstResponder.current() is UITextInput { return }
            becomeFirstResponder()
        }

        private var mayUseKeys: Bool {
            window?.isKeyWindow == true && !sheetIsUp && !ToolShortcuts.typeToJumpActive
        }

        private func arrow(_ code: UIKeyboardHIDUsage) -> (Int, Int)? {
            switch code {
            case .keyboardLeftArrow:  (-1, 0)
            case .keyboardRightArrow: (1, 0)
            case .keyboardDownArrow:  (0, 1)
            case .keyboardUpArrow:    (0, -1)
            default: nil
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard mayUseKeys, presses.count == 1, let key = presses.first?.key,
                  key.modifierFlags.intersection([.command, .alternate, .control]).isEmpty else {
                return super.pressesBegan(presses, with: event)
            }
            let big = key.modifierFlags.contains(.shift)
            if let d = arrow(key.keyCode) {
                guard onArrow(d.0, d.1, big) else { return super.pressesBegan(presses, with: event) }
                held.insert(key.keyCode)
                startRepeat(d, big)
                return
            }
            // 014 — Space paints at the pixel cursor (Pen only; otherwise passed on).
            if key.keyCode == .keyboardSpacebar {
                guard onPaint() else { return super.pressesBegan(presses, with: event) }
                held.insert(key.keyCode)
                return
            }
            let chars = key.charactersIgnoringModifiers
            if chars.count == 1, let ch = chars.first, let tool = Tool.forShortcut(ch) {
                held.insert(key.keyCode)
                onPick(tool)
                return
            }
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            finish(presses) { super.pressesEnded($0, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            finish(presses) { super.pressesCancelled($0, with: event) }
        }

        private func finish(_ presses: Set<UIPress>, passOn: (Set<UIPress>) -> Void) {
            var rest = presses
            for p in presses {
                if let k = p.key, held.remove(k.keyCode) != nil {
                    rest.remove(p)
                    if arrow(k.keyCode) != nil { stopRepeat() }
                }
            }
            if !rest.isEmpty { passOn(rest) }
        }

        // A held arrow keeps moving: a pause like the system key repeat, then steady steps.
        private func startRepeat(_ d: (Int, Int), _ big: Bool) {
            stopRepeat()
            repeatTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled, let self {
                    guard self.mayUseKeys, self.onArrow(d.0, d.1, big) else { return }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        private func stopRepeat() { repeatTask?.cancel(); repeatTask = nil }
    }
}

/// Which responder has the keyboard right now (UIKit doesn't say; a nil-target action asks).
@MainActor
enum FirstResponder {
    fileprivate static weak var found: UIResponder?
    static func current() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.imageProducerReportFirstResponder(_:)),
                                        to: nil, from: nil, for: nil)
        return found
    }
}

extension UIResponder {
    @objc fileprivate func imageProducerReportFirstResponder(_ sender: Any?) {
        FirstResponder.found = self
    }
}
#endif
