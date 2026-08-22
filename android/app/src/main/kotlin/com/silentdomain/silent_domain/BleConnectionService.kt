package com.silentdomain.silent_domain

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 仅在用户已经建立静域连接后运行的 Android 前台服务。
 *
 * 服务本身不读取或保存聊天资料，只提高现有 Flutter/BLE 进程在后台处理
 * 通知与确认包的存活优先级。用户主动断开或划掉任务后会立即停止。
 */
class BleConnectionService : Service() {
    companion object {
        private const val notificationChannelId = "silent_domain_ble_connection"
        private const val notificationId = 4107

        fun start(context: Context) {
            val intent = Intent(context, BleConnectionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BleConnectionService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(notificationId, buildNotification())
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            notificationChannelId,
            "静域连接",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持已建立的蓝牙离线连接"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("静域连接正在运行")
            .setContentText("保持蓝牙离线消息传输")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .build()
    }
}
