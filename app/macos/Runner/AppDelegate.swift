import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The music goes on with no window (spec UI §4.2): ⌘Q or the Dock's « Quitter » quits.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Closing the window only hides it (the music goes on): the Dock icon brings it back.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows { window.makeKeyAndOrderFront(self) }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
