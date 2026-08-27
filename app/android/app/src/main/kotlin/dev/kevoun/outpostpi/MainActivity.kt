package dev.kevoun.outpostpi

import android.view.WindowInsets
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var imeVisibilityChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imeVisibilityChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IME_VISIBILITY_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isVisible" -> {
                            val visible =
                                window.decorView.rootWindowInsets
                                    ?.isVisible(WindowInsets.Type.ime()) == true
                            result.success(visible)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        imeVisibilityChannel?.setMethodCallHandler(null)
        imeVisibilityChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val IME_VISIBILITY_CHANNEL = "dev.kevoun.outpostpi/ime-visibility"
    }
}
