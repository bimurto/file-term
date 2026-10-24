import AppKit
import FileTermCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let provider = LocalFileSystemProvider()
  private lazy var pane = PaneModel(providers: [provider])
  private lazy var settings = AppSettings(suite: settingsSuite)
  private lazy var settingsCoordinator = SettingsCoordinator(settings: settings)
  private var browserWindow: NSWindow?
  private var menuCoordinator: MenuCoordinator?

  private var settingsSuite: UserDefaults {
    if let name = ProcessInfo.processInfo.environment["FILETERM_SETTINGS_SUITE"],
      let suite = UserDefaults(suiteName: name)
    {
      return suite
    }
    return .standard
  }

  private lazy var registry = CommandRegistry(
    commands: makeCommands(),
    context: { [unowned self] in
      CommandContext(
        hasBrowserWindow: browserWindow?.isVisible == true,
        hasKeyWindow: NSApp.keyWindow != nil, isLoading: pane.isLoading
      )
    }
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    menuCoordinator = MenuCoordinator(registry: registry)
    menuCoordinator?.install()
    showBrowser()
    let initialURL =
      ProcessInfo.processInfo.environment["FILETERM_INITIAL_DIRECTORY"]
      .map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    Task { await pane.navigate(to: provider.location(for: initialURL)) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showBrowser()
    return true
  }

  private func showBrowser() {
    if browserWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false
      )
      window.title = "FileTerm"
      window.identifier = NSUserInterfaceItemIdentifier("browserWindow")
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(
        rootView: BrowserView(
          pane: pane, settings: settings, registry: registry, localProvider: provider)
      )
      window.center()
      browserWindow = window
    }
    browserWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }

  private func openDownloads() {
    do {
      showBrowser()
      let url = try FileManager.default.url(
        for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
      Task { await pane.navigate(to: provider.location(for: url)) }
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  private func makeCommands() -> [AppCommand] {
    var commands: [AppCommand] = [
      AppCommand(
        id: "app.about", title: "About FileTerm", menuPath: ["FileTerm"], isEnabled: { _ in true },
        disabledReason: { _ in "" },
        handler: {
          NSApp.orderFrontStandardAboutPanel(nil)
        }
      ),
      AppCommand(
        id: "app.settings", title: "Settings…", menuPath: ["FileTerm"], shortcut: ",",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in
          self?.settingsCoordinator.show()
        }
      ),
      AppCommand(
        id: "app.hide", title: "Hide FileTerm", menuPath: ["FileTerm"], shortcut: "h",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: {
          NSApp.hide(nil)
        }
      ),
      AppCommand(
        id: "app.quit", title: "Quit FileTerm", menuPath: ["FileTerm"], shortcut: "q",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: {
          NSApp.terminate(nil)
        }
      ),
      AppCommand(
        id: "file.showBrowser", title: "Show Browser Window", menuPath: ["File"],
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in
          self?.showBrowser()
        }
      ),
      AppCommand(
        id: "file.close", title: "Close Window", menuPath: ["File"], shortcut: "w",
        isEnabled: { $0.hasKeyWindow }, disabledReason: { _ in "No window is open." },
        handler: {
          NSApp.keyWindow?.performClose(nil)
        }
      ),
      AppCommand(
        id: "go.downloads", title: "Downloads", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in
          self?.openDownloads()
        }
      ),
      AppCommand(
        id: "window.minimize", title: "Minimize", menuPath: ["Window"], shortcut: "m",
        isEnabled: { _ in NSApp.keyWindow?.styleMask.contains(.miniaturizable) == true },
        disabledReason: { _ in "This window cannot be minimized." },
        handler: {
          NSApp.keyWindow?.performMiniaturize(nil)
        }
      ),
      AppCommand(
        id: "window.zoom", title: "Zoom", menuPath: ["Window"],
        isEnabled: { _ in NSApp.keyWindow?.styleMask.contains(.resizable) == true },
        disabledReason: { _ in "This window cannot be resized." },
        handler: {
          NSApp.keyWindow?.performZoom(nil)
        }
      ),
    ]
    for panel in PlaceholderPanel.allCases {
      commands.append(
        AppCommand(
          id: panel.commandID, title: "Show/Hide \(panel.rawValue)", menuPath: ["View"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in self?.settings.toggle(panel) }
        ))
    }
    return commands
  }
}
