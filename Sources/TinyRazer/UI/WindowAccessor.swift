import SwiftUI
import AppKit

/// Transparent SwiftUI view that exposes the hosting `NSWindow` via a
/// configuration closure — run once when the view is inserted into the
/// window hierarchy. Used to tweak window chrome (hide minimise / zoom
/// buttons, etc.) that SwiftUI's `Window` scene doesn't expose.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

extension View {
    /// Hide the minimise and zoom traffic-light buttons on the hosting
    /// window. The close (red) button stays active.
    func hideMinimiseAndZoomButtons() -> some View {
        background(WindowAccessor { window in
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        })
    }
}
