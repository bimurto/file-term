import FileTermCore
import SwiftUI

struct PaneTabBar: View {
  let browser: BrowserModel
  let paneID: PaneID
  let registry: CommandRegistry

  var body: some View {
    HStack(spacing: 4) {
      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(browser.tabs(paneID).tabs, id: \.id) { tab in
            HStack(spacing: 4) {
              Button {
                browser.activePaneID = paneID
                browser.selectTab(tab.id, in: paneID)
              } label: {
                HStack(spacing: 4) {
                  if tab.isPinned { Image(systemName: "pin.fill").font(.caption2) }
                  Text(title(tab)).lineLimit(1)
                }.padding(.horizontal, 7).padding(.vertical, 4)
              }
              .buttonStyle(.plain).accessibilityIdentifier("tab.\(paneID.rawValue).\(tab.id)")
              .accessibilityValue(browser.pane(paneID) === tab ? "Selected" : "")
              if browser.tabs(paneID).tabs.count > 1 {
                Button {
                  browser.activePaneID = paneID
                  browser.closeTab(tab.id, in: paneID)
                } label: {
                  Image(systemName: "xmark").font(.caption2).padding(4)
                }
                .buttonStyle(.plain).accessibilityLabel("Close tab \(title(tab))")
              }
            }
            .background(
              browser.pane(paneID) === tab ? Color.accentColor.opacity(0.15) : .clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
            .help(tab.location?.path ?? "No folder open")
          }
        }
      }.scrollIndicators(.hidden)
      Button {
        browser.activePaneID = paneID
        registry.execute("file.newTab")
      } label: {
        Image(systemName: "plus").padding(5)
      }
      .buttonStyle(.plain).accessibilityLabel("New Tab").accessibilityIdentifier(
        "newTab.\(paneID.rawValue)")
    }.padding(.horizontal, 6).frame(height: 30).contentShape(Rectangle())
      .onTapGesture(count: 2) {
        // Double-clicking the empty part of the bar opens a tab at Home.
        browser.activePaneID = paneID
        registry.execute("file.newTab")
        registry.execute(StandardDestination.home.commandID)
      }
      .accessibilityElement(children: .contain).accessibilityIdentifier("tabBar.\(paneID.rawValue)")
  }

  private func title(_ tab: PaneModel) -> String {
    guard let path = tab.location?.path else { return "New Tab" }
    return path == "/" ? "/" : URL(fileURLWithPath: path).lastPathComponent
  }
}
