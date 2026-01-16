#!/bin/bash

# --- Configuration ---
APP_NAME="Time Beeps"
PACKAGE_DIR="app/src/main/java/com/example/myapplication"
LAYOUT_DIR="app/src/main/res/layout"
MANIFEST_DIR="app/src/main"

echo "Creating Project Structure for $APP_NAME..."

mkdir -p "$APP_NAME/$PACKAGE_DIR"
mkdir -p "$APP_NAME/$LAYOUT_DIR"

cd "$APP_NAME" || exit

# --- 1. Java Version Fix (CRITICAL for Arch/Java 25 Users) ---
echo "Configuring Java Version..."

# Standard Arch Linux path for OpenJDK 17
ARCH_JAVA17="/usr/lib/jvm/java-17-openjdk"

if [ -d "$ARCH_JAVA17" ]; then
    echo "Found OpenJDK 17 at $ARCH_JAVA17"
    echo "org.gradle.java.home=$ARCH_JAVA17" > gradle.properties
    
    # Temporarily force JAVA_HOME for the 'gradle wrapper' command later
    export JAVA_HOME="$ARCH_JAVA17"
    export PATH="$JAVA_HOME/bin:$PATH"
else
    echo "⚠️ WARNING: OpenJDK 17 not found at $ARCH_JAVA17"
    echo "   Android builds REQUIRE Java 17. Your Java 25 will likely fail."
    echo "   Please run: sudo pacman -S jdk17-openjdk"
    echo "   Then run this script again."
    # We continue, but expect failure if system java is 25
fi

# --- 2. Generate Build Files ---

echo "Generating Gradle files..."

# settings.gradle.kts
cat <<EOF > settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "BeepApp"
include(":app")
EOF

# build.gradle.kts (Root)
cat <<EOF > build.gradle.kts
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# app/build.gradle.kts
cat <<EOF > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.myapplication"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.myapplication"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# --- 3. Generate Code Files ---

echo "Generating Source Code..."

# AndroidManifest.xml
cat <<EOF > $MANIFEST_DIR/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="Beep App"
        android:theme="@style/Theme.AppCompat.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".BeepService"
            android:enabled="true"
            android:exported="false"
            android:foregroundServiceType="specialUse">
        </service>

    </application>
</manifest>
EOF

# BeepService.kt
cat <<EOF > $PACKAGE_DIR/BeepService.kt
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
EOF

# MainActivity.kt
cat <<EOF > $PACKAGE_DIR/MainActivity.kt
package com.example.myapplication

import android.Manifest
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.btnStart).setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                if (!am.canScheduleExactAlarms()) {
                    startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
                    Toast.makeText(this, "Please allow Exact Alarms!", Toast.LENGTH_LONG).show()
                    return@setOnClickListener
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
                    return@setOnClickListener
                }
            }
            startForegroundService(Intent(this, BeepService::class.java))
            findViewById<TextView>(R.id.statusText).text = "Status: ACTIVE"
        }

        findViewById<Button>(R.id.btnStop).setOnClickListener {
            stopService(Intent(this, BeepService::class.java))
            findViewById<TextView>(R.id.statusText).text = "Status: STOPPED"
        }
    }
}
EOF

# activity_main.xml
cat <<EOF > $LAYOUT_DIR/activity_main.xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="16dp">
    <TextView
        android:id="@+id/statusText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Status: STOPPED"
        android:textSize="24sp"
        android:layout_marginBottom="32dp"/>
    <Button
        android:id="@+id/btnStart"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Start 24/7 Beep"
        android:padding="16dp"/>
    <Button
        android:id="@+id/btnStop"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Stop"
        android:layout_marginTop="16dp"
        android:padding="16dp"/>
</LinearLayout>
EOF

# --- 4. Arch Linux Specific Fixes ---

echo "Detecting Android SDK..."

# Try to find SDK location if not set
if [ -z "$ANDROID_HOME" ]; then
    if [ -d "/opt/android-sdk" ]; then
        export ANDROID_HOME=/opt/android-sdk
    elif [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_HOME=$HOME/Android/Sdk
    else
        echo "WARNING: Could not find Android SDK. Please set ANDROID_HOME manually."
    fi
fi

if [ ! -z "$ANDROID_HOME" ]; then
    echo "Creating local.properties with sdk.dir=$ANDROID_HOME"
    echo "sdk.dir=$ANDROID_HOME" > local.properties
else
    echo "skipping local.properties (ANDROID_HOME not found)"
fi

# --- 5. Bootstrap Gradle Wrapper ---
# This fixes the "Version Hell" issue by generating the wrapper using your system gradle
# but locking it to the version the project needs.

echo "Bootstrapping Gradle Wrapper..."
# Note: we are running this with the JAVA_HOME set to JDK 17 above
gradle wrapper --gradle-version 8.7

echo "----------------------------------------------------"
echo "Done! To build and install:"
echo "1. Connect your phone (USB Debugging ON)"
echo "2. cd $APP_NAME"
echo "3. ./gradlew installDebug"
echo "----------------------------------------------------"
