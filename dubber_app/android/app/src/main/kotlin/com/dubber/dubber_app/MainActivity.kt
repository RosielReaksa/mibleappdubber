package com.dubber.dubber_app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dubber.dubber_app/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApkPath" -> {
                    try {
                        val sourcePath = packageManager
                            .getApplicationInfo(packageName, 0)
                            .sourceDir
                        result.success(sourcePath)
                    } catch (error: Exception) {
                        result.error("installed_apk_unavailable", error.message, null)
                    }
                }
                "installPatchedApk" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_apk_path", "Missing APK path.", null)
                            return@setMethodCallHandler
                        }
                        val updateRoot = File(filesDir, "ota_update").canonicalFile
                        val apk = File(path).canonicalFile
                        if (!apk.path.startsWith(updateRoot.path + File.separator) ||
                            !apk.isFile || !apk.canRead()
                        ) {
                            result.error("invalid_apk_path", "The rebuilt APK is not in update storage.", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.ota_update_provider",
                            apk,
                        )
                        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                            data = uri
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("install_intent_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
