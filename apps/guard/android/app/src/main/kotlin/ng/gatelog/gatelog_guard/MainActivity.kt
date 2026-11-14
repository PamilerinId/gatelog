package ng.gatelog.gatelog_guard

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var roleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A rider's shift runs a location foreground service. On Android 13 and up its
        // notification shows only once the rider allows notifications, so ask when the shift opens.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ng.gatelog/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Caller ID: the call-screening role (Android 10+) and the last incoming call it noted.
        // The number goes to Dart only; it is never logged here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ng.gatelog/caller").setMethodCallHandler { call, result ->
            when (call.method) {
                "lastIncoming" -> result.success(LastCall.read())
                "hasRole" -> result.success(holdsRole())
                "requestRole" -> requestRole(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun roleManager(): RoleManager? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) getSystemService(RoleManager::class.java) else null

    private fun holdsRole(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val rm = roleManager() ?: return false
        return rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) && rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    private fun requestRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return result.success(false)
        val rm = roleManager()
        if (rm == null || !rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) return result.success(false)
        if (rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) return result.success(true)
        if (roleResult != null) return result.success(false)
        roleResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING), ROLE_REQUEST)
        } catch (e: Exception) {
            roleResult = null
            result.success(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ROLE_REQUEST) {
            roleResult?.success(holdsRole())
            roleResult = null
        }
    }

    companion object {
        private const val ROLE_REQUEST = 7302
    }
}
