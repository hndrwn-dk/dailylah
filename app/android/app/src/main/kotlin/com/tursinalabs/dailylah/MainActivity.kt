package com.tursinalabs.dailylah

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens an installed app (e.g. Grab) by package name. Returns false when it is not
        // installed, so Dart can fall back to the Play Store page.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dailylah/apps")
            .setMethodCallHandler { call, result ->
                if (call.method != "launch") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val pkg = call.argument<String>("package")
                val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                if (intent == null) {
                    result.success(false)
                } else {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
            }
    }
}
