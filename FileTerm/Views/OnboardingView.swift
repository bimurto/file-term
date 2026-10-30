import AppKit
import FileTermCore
import SwiftUI
import UserNotifications

/// The first-run guide. It is an ordinary window, so the browser stays usable behind it.
@MainActor final class OnboardingCoordinator {
  private var window: NSWindow?

  /// UI tests and test hosts set their own environment and must not get an extra window.
  static func shouldShow(alreadyShown: Bool, environment: [String: String]) -> Bool {
    if environment["FILETERM_SHOW_ONBOARDING"] != nil { return true }
    let automated = environment.keys.contains {
      $0.hasPrefix("FILETERM_") || $0 == "XCTestConfigurationFilePath"
    }
    return !alreadyShown && !automated
  }

  func show() {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: OnboardingView { [weak self] in self?.window?.close() }))
    window.title = String(localized: "Welcome to FileTerm")
    window.identifier = NSUserInterfaceItemIdentifier("onboardingWindow")
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
  }
}

private struct OnboardingView: View {
  let close: () -> Void
  @State private var notificationStatus: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Welcome to FileTerm").font(.title2).fontWeight(.semibold)
      VStack(alignment: .leading, spacing: 6) {
        Text("Full Disk Access").font(.headline)
        Text(
          "macOS protects some folders, such as Mail and other apps' data. Give FileTerm Full Disk Access if you want to browse them. You can skip this and still use your other folders."
        ).fixedSize(horizontal: false, vertical: true)
        Button("Open Full Disk Access Settings") {
          NSWorkspace.shared.open(SystemPermission.fullDiskAccess.settingsURL)
        }.accessibilityIdentifier("openFullDiskAccess")
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Notifications").font(.headline)
        Text(
          "FileTerm does not send notifications yet. Allowing them now means it will not ask later."
        )
        .fixedSize(horizontal: false, vertical: true)
        Button("Allow Notifications", action: requestNotifications)
          .accessibilityIdentifier("allowNotifications")
        if let notificationStatus {
          Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("notificationStatus")
        }
      }
      HStack {
        Spacer()
        Button("Done", action: close).keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("finishOnboarding")
      }
    }
    .padding(24).frame(width: 460)
  }

  private func requestNotifications() {
    Task {
      let allowed =
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound,
        ])) == true
      notificationStatus =
        allowed
        ? String(localized: "Notifications are allowed.")
        : String(localized: "Notifications are off. You can change this in System Settings.")
    }
  }
}
