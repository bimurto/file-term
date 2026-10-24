import AppKit
import SwiftUI

struct PathBar: NSViewRepresentable {
  let url: URL?
  let displayPath: String?

  func makeNSView(context: Context) -> NSPathControl {
    let control = NSPathControl()
    control.pathStyle = .standard
    control.isEditable = false
    control.setAccessibilityIdentifier("currentPath")
    control.setAccessibilityLabel("Current folder")
    control.unregisterDraggedTypes()
    return control
  }

  func updateNSView(_ control: NSPathControl, context: Context) {
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
