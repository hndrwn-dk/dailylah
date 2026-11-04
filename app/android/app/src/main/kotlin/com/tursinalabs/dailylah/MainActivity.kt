package com.tursinalabs.dailylah

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// Text shared to DailyLah (Share > DailyLah) that Dart has not taken yet.
    private var pendingShare: Map<String, String?>? = null
    private var shareChannel: MethodChannel? = null

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

        // A place shared from Google Maps: "take" hands over the one that opened the app (once);
        // later shares while the app runs are pushed with "shared".
        pendingShare = sharedText(intent)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dailylah/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pendingShare)
                    pendingShare = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val shared = sharedText(intent) ?: return
        setIntent(intent)
        val channel = shareChannel
        if (channel == null) {
            pendingShare = shared
        } else {
            channel.invokeMethod("shared", shared)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun sharedText(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.take(2000)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.take(200)
        if (text.isNullOrBlank() && subject.isNullOrBlank()) return null
        // Taken once: a later recreate (rotation, dark-mode switch) must not share it again.
        intent.action = null
        return mapOf("text" to text, "subject" to subject)
    }
}
