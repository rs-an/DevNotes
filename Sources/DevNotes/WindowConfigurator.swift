import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWindow(from: view)
    }

    private func configureWindow(from view: NSView) {
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
    }
}
