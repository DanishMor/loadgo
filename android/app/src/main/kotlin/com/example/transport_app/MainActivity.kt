package com.example.transport_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createPushChannels()
    }

    // F24: the push channels. The server names one of these in every message
    // (functions/src/push.js); the person can switch each off in the phone settings.
    // Names are translated in res/values-*/push_channels.xml.
    private fun createPushChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            Triple("bookings", R.string.channel_bookings, NotificationManager.IMPORTANCE_HIGH),
            Triple("chat", R.string.channel_chat, NotificationManager.IMPORTANCE_HIGH),
            Triple("payments", R.string.channel_payments, NotificationManager.IMPORTANCE_HIGH),
            Triple("offers", R.string.channel_offers, NotificationManager.IMPORTANCE_DEFAULT),
            Triple("admin", R.string.channel_admin, NotificationManager.IMPORTANCE_HIGH),
        )
        for ((id, name, importance) in channels) {
            manager.createNotificationChannel(NotificationChannel(id, getString(name), importance))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // F4: the app turns FLAG_SECURE on while a sensitive screen is open
        // (no screenshots, no screen recording, blank thumbnail in recent apps).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loadgo/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    val on = call.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
