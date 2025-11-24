package com.smartattendance.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity with Method Channel for BLE service control
 * 
 * Provides Flutter interface to:
 * - Start/stop BLE scanning service
 * - Configure authentication and API settings
 * - Receive attendance events from native service
 */
class MainActivity: FlutterActivity() {
    
    private val CHANNEL = "com.smartattendance.app/ble"
    private lateinit var methodChannel: MethodChannel
    
    private val attendanceEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.smartattendance.app.ATTENDANCE_EVENT") {
                val studentId = intent.getStringExtra("student_id")
                val beaconId = intent.getStringExtra("beacon_id")
                val event = intent.getStringExtra("event")
                val timestamp = intent.getStringExtra("timestamp")
                
                // Notify Flutter
                val eventData = mapOf(
                    "student_id" to studentId,
                    "beacon_id" to beaconId,
                    "event" to event,
                    "timestamp" to timestamp
                )
                
                methodChannel.invokeMethod("onAttendanceEvent", eventData)
                
                android.util.Log.i("MainActivity", 
                    "Attendance event received: $studentId at $beaconId -> $event")
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBleService" -> {
                    val authToken = call.argument<String>("authToken")
                    val studentId = call.argument<String>("studentId")
                    val apiBaseUrl = call.argument<String>("apiBaseUrl")
                    
                    if (authToken != null && studentId != null) {
                        // Save credentials to shared preferences
                        val prefs = getSharedPreferences(
                            BleScanService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        prefs.edit().apply {
                            putString(BleScanService.KEY_AUTH_TOKEN, authToken)
                            putString(BleScanService.KEY_STUDENT_ID, studentId)
                            putString(BleScanService.KEY_API_BASE_URL, 
                                apiBaseUrl ?: "https://api.example.com")
                            apply()
                        }
                        
                        // Start BLE scanning service
                        val intent = Intent(this, BleScanService::class.java).apply {
                            action = BleScanService.ACTION_START_SCANNING
                        }
                        
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        
                        android.util.Log.i("MainActivity", "BLE service started")
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing authToken or studentId", null)
                    }
                }
                
                "stopBleService" -> {
                    val intent = Intent(this, BleScanService::class.java).apply {
                        action = BleScanService.ACTION_STOP_SCANNING
                    }
                    stopService(intent)
                    
                    android.util.Log.i("MainActivity", "BLE service stopped")
                    result.success(true)
                }
                
                "isServiceRunning" -> {
                    result.success(BleScanService.isServiceRunning)
                }
                
                "updateAuthToken" -> {
                    val authToken = call.argument<String>("authToken")
                    if (authToken != null) {
                        val prefs = getSharedPreferences(
                            BleScanService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        prefs.edit().putString(BleScanService.KEY_AUTH_TOKEN, authToken).apply()
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing authToken", null)
                    }
                }
                
                "getLastBeaconState" -> {
                    val prefs = getSharedPreferences(
                        BleScanService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    val lastState = prefs.getString(BleScanService.KEY_LAST_BEACON_STATE, null)
                    result.success(lastState)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Register broadcast receiver for attendance events
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                attendanceEventReceiver,
                IntentFilter("com.smartattendance.app.ATTENDANCE_EVENT"),
                RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(
                attendanceEventReceiver,
                IntentFilter("com.smartattendance.app.ATTENDANCE_EVENT")
            )
        }
        
        android.util.Log.i("MainActivity", "Method channel configured")
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(attendanceEventReceiver)
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "Error unregistering receiver", e)
        }
    }
}
