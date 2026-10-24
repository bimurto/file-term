import AppKit
import SwiftUI

/// Observes native table clicks without consuming their selection or double-click events.
struct PaneActivationView: NSViewRepresentable {
  let onActivate: () -> Void

  func makeNSView(context: Context) -> ActivationView {
    let view = ActivationView()
    view.onActivate = onActivate
    return view
  }

  func updateNSView(_ view: ActivationView, context: Context) { view.onActivate = onActivate }
  static func dismantleNSView(_ view: ActivationView, coordinator: ()) { view.stopMonitoring() }

  @MainActor final class ActivationView: NSView {
    var onActivate: () -> Void = {}
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
        [weak self] event in
        MainActor.assumeIsolated {
          if let self, let window = self.window, event.window === window,
            self.bounds.contains(self.convert(event.locationInWindow, from: nil))
          {
            self.onActivate()
          }
        }
        return event
      }
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
