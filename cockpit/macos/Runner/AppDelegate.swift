import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Ignora SIGPIPE no processo inteiro (disposição de sinal é por-processo,
    // não por-thread → cobre a platform/UI thread mesclada). Sem isso, qualquer
    // escrita num pipe sem leitor — spawn de language server que falha, PTY de
    // terminal fechado, processo `pi --mode rpc` que sumiu junto com uma worktree
    // deletada — entrega SIGPIPE e derruba o app inteiro, sem dialog nem crash
    // report. A Dart VM normalmente seta SIG_IGN, mas o embedder Flutter macOS no
    // modo "merged UI and platform thread (Experimental)" não o herda.
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
