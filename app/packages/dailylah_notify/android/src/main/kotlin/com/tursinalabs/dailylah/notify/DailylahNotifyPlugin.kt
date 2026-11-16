package com.tursinalabs.dailylah.notify

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Channel `dailylah/notify`. A real plugin (not a channel in MainActivity) because most
 * alerts are posted from the WorkManager isolate, whose engine only has registered plugins.
 * `show` answers true when the notification was posted and false otherwise: the Dart side
 * then shows the plain notification, so an alert is never lost to this layout.
 */
class DailylahNotifyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dailylah/notify").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "show") {
            result.notImplemented()
            return
        }
        val ctx = context
        val posted = try {
            val note = call.argument<Map<String, Any?>>("note")
            ctx != null && note != null && NotePoster.post(
                ctx,
                note,
                call.argument<String>("channelName") ?: "DailyLah alerts",
                call.argument<String>("channelDescription") ?: "",
            )
        } catch (e: Throwable) {
            // Also an Error (out of memory for a bitmap, a method a phone's Android lacks):
            // the plain notification is better than a crashed background check.
            Log.w("DailylahNotify", "rich notification not posted", e)
            false
        }
        result.success(posted)
    }
}
