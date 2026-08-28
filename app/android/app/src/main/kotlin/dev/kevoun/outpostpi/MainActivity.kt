package dev.kevoun.outpostpi

import android.view.WindowInsets
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var imeVisibilityChannel: MethodChannel? = null
    private var imeRecoveryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imeVisibilityChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IME_VISIBILITY_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isVisible" -> {
                            val visible = runCatching {
                                window.decorView.rootWindowInsets
                                    ?.isVisible(WindowInsets.Type.ime()) == true
                            }.getOrDefault(false)
                            result.success(visible)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        imeRecoveryChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IME_RECOVERY_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "recover" -> recoverIme(result)
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun recoverIme(result: MethodChannel.Result) {
        if (isFinishing || isDestroyed) {
            result.success(false)
            return
        }
        val hostWindow = runCatching { window }.getOrNull()
        val hostView = hostWindow?.decorView
        if (hostWindow == null || hostView == null) {
            result.success(false)
            return
        }
        runCatching {
            WindowInsetsControllerCompat(hostWindow, hostView)
                .hide(WindowInsetsCompat.Type.ime())
            // Ask the view to publish a fresh inset pass even when the IME was
            // already hidden from the controller's perspective.
            hostView.requestApplyInsets()
        }.onSuccess {
            result.success(true)
        }.onFailure {
            result.success(false)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        imeVisibilityChannel?.setMethodCallHandler(null)
        imeVisibilityChannel = null
        imeRecoveryChannel?.setMethodCallHandler(null)
        imeRecoveryChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val IME_VISIBILITY_CHANNEL = "dev.kevoun.outpostpi/ime-visibility"
        const val IME_RECOVERY_CHANNEL = "dev.kevoun.outpostpi/ime-recovery"
    }
}
