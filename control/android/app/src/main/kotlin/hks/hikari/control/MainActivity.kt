package hks.hikari.control

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "hks.hikari.control/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCpuAbi" -> {
                    val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
                    result.success(abi)
                }
                else -> result.notImplemented()
            }
        }
    }
}
