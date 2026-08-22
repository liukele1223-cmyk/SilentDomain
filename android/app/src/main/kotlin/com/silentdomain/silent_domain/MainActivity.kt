package com.silentdomain.silent_domain

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val backgroundChannel =
            "com.silentdomain.silent_domain/ble_background"
        private const val notificationPermissionRequestCode = 4108
        private const val permissionPreferences = "silent_domain_permissions"
        private const val notificationPermissionRequested =
            "notification_permission_requested"
    }

    private val pendingBackgroundStartResults = mutableListOf<MethodChannel.Result>()
    private var notificationPermissionRequestInFlight = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startBackgroundService(result)

                    "stop" -> {
                        BleConnectionService.stop(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun startBackgroundService(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            val preferences = getSharedPreferences(permissionPreferences, MODE_PRIVATE)
            val wasRequested = preferences.getBoolean(notificationPermissionRequested, false)
            if (!wasRequested || notificationPermissionRequestInFlight) {
                pendingBackgroundStartResults.add(result)
                if (!notificationPermissionRequestInFlight) {
                    notificationPermissionRequestInFlight = true
                    preferences.edit()
                        .putBoolean(notificationPermissionRequested, true)
                        .apply()
                    requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        notificationPermissionRequestCode,
                    )
                }
                return
            }
            startBackgroundServiceNow(result, notificationVisible = false)
            return
        }
        startBackgroundServiceNow(result, notificationVisible = true)
    }

    private fun startBackgroundServiceNow(
        result: MethodChannel.Result,
        notificationVisible: Boolean,
    ) {
        try {
            BleConnectionService.start(this)
            result.success(
                if (notificationVisible) {
                    "notificationVisible"
                } else {
                    "notificationUnavailable"
                },
            )
        } catch (_: Exception) {
            result.success("failed")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        notificationPermissionRequestInFlight = false
        val notificationVisible =
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        val pendingResults = pendingBackgroundStartResults.toList()
        pendingBackgroundStartResults.clear()
        for (result in pendingResults) {
            startBackgroundServiceNow(result, notificationVisible)
        }
    }
}
