import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Ignore SIGPIPE for the whole process (signal disposition is per-process,
    // not per-thread → covers the merged platform/UI thread). Without this, any
    // write to a pipe with no reader — a language-server spawn that fails, a
    // closed terminal PTY, a `pi --mode rpc` process that vanished along with a
    // deleted worktree — delivers SIGPIPE and crashes the whole app, with no
    // dialog or crash report. The Dart VM normally sets SIG_IGN, but the Flutter
    // macOS embedder in "merged UI and platform thread (Experimental)" mode does
    // not inherit it.
    signal(SIGPIPE, SIG_IGN)
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
