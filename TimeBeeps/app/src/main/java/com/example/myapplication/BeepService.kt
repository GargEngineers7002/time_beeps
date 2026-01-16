package com.example.myapplication

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.util.Calendar

class BeepService : Service() {

    private var toneGenerator: ToneGenerator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val CHANNEL_ID = "BeepServiceChannel"
        const val ACTION_BEEP = "com.example.myapplication.ACTION_BEEP"
        const val ACTION_STOP = "com.example.myapplication.ACTION_STOP"
    }

    override fun onCreate() {
        super.onCreate()
        toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BeepApp::BeepLock")
        createNotificationChannel()
        startForeground(1, createNotification())
        scheduleNextBeep()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_BEEP) {
            performBeep()
            scheduleNextBeep()
        } else if (intent?.action == ACTION_STOP) {
            stopSelf()
        }
        return START_STICKY
    }

    private fun performBeep() {
        wakeLock?.acquire(2000L)
        try {
            toneGenerator?.startTone(ToneGenerator.TONE_CDMA_PIP, 150)
            Log.d("BeepService", "TING!")
        } catch (e: Exception) {
            Log.e("BeepService", "Error", e)
        } finally {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        }
    }

    private fun scheduleNextBeep() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, BeepService::class.java).apply { action = ACTION_BEEP }
        val pendingIntent = PendingIntent.getService(
            this, 0, intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val calendar = Calendar.getInstance()
        calendar.timeInMillis = System.currentTimeMillis()
        calendar.add(Calendar.MINUTE, 1)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        // Android 12+ requires specific permissions for exact alarms, 
        // but this method is the strongest way to request wake-up.
        try {
             alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent
            )
        } catch (e: SecurityException) {
            Log.e("BeepService", "Permission missing for exact alarm")
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, BeepService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE
        )
        // Using a built-in icon to avoid resource errors
        val icon = android.R.drawable.ic_lock_idle_alarm

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
             Notification.Builder(this)
        }

        return builder
            .setContentTitle("Minute Beeper Active")
            .setContentText("Running 24/7. Tap 'Stop' to kill.")
            .setSmallIcon(icon)
            .addAction(Notification.Action.Builder(null, "STOP", stopPendingIntent).build())
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID, "Beep Service Channel", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(serviceChannel)
        }
    }

    override fun onDestroy() {
        toneGenerator?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
