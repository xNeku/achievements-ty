package com.xneku.hangar

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Instalar APKs de ports, saber si siguen instalados, abrirlos y desinstalarlos.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hangar/android").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "packageOf" -> {
                        val path = call.arguments as String
                        val info = packageManager.getPackageArchiveInfo(path, 0)
                        result.success(info?.packageName)
                    }
                    "install" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(false)
                        } else {
                            val file = File(call.arguments as String)
                            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                    }
                    "isInstalled" -> {
                        val pkg = call.arguments as String?
                        result.success(pkg != null && packageManager.getLaunchIntentForPackage(pkg) != null)
                    }
                    "launch" -> {
                        val pkg = call.arguments as String?
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent == null) {
                            result.success(false)
                        } else {
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        }
                    }
                    "uninstall" -> {
                        val pkg = call.arguments as String
                        startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "hasUsage" -> result.success(tieneUso())
                    "askUsage" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "usage" -> {
                        // Tiempo en primer plano de cada port desde hace dos años (lo que guarde el sistema).
                        @Suppress("UNCHECKED_CAST")
                        val pkgs = call.arguments as List<String>
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val now = System.currentTimeMillis()
                        val stats = usm.queryAndAggregateUsageStats(now - 2L * 365 * 24 * 3600 * 1000, now)
                        val out = HashMap<String, Any>()
                        for (p in pkgs) {
                            val s = stats[p] ?: continue
                            out[p] = mapOf("ms" to s.totalTimeInForeground, "last" to s.lastTimeUsed)
                        }
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("hangar", e.message, null)
            }
        }
    }

    private fun tieneUso(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
