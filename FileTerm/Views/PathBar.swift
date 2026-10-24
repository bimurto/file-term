import AppKit
import SwiftUI

struct PathBar: NSViewRepresentable {
  let url: URL?
  let displayPath: String?
  var onNavigate: (URL) -> Void = { _ in }

  func makeCoordinator() -> Coordinator { Coordinator(onNavigate: onNavigate) }

  func makeNSView(context: Context) -> NSPathControl {
    let control = NSPathControl()
    control.pathStyle = .standard
    control.target = context.coordinator
    control.action = #selector(Coordinator.clicked(_:))
    control.isEditable = false
    control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    control.setAccessibilityIdentifier("currentPath")
    control.setAccessibilityLabel("Current folder")
    control.unregisterDraggedTypes()
    return control
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPathControl, context: Context)
    -> CGSize?
  {
    CGSize(width: proposal.width ?? 200, height: 24)
  }

  @MainActor final class Coordinator: NSObject {
    var onNavigate: (URL) -> Void
    init(onNavigate: @escaping (URL) -> Void) { self.onNavigate = onNavigate }
    @objc func clicked(_ sender: NSPathControl) {
      guard let url = sender.clickedPathItem?.url else { return }
      onNavigate(url)
    }
  }

  func updateNSView(_ control: NSPathControl, context: Context) {
    context.coordinator.onNavigate = onNavigate
    control.url = url
    if url == nil, let displayPath {
      let item = NSPathControlItem()
      item.title = displayPath
      control.pathItems = [item]
    }
    control.toolTip = displayPath
    control.setAccessibilityValue(displayPath ?? "No folder open")
  }
}
