package com.smartattendance.app

import android.annotation.SuppressLint
import android.app.*
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Production-level BLE Foreground Service
 * 
 * Features:
 * - Continuous BLE scanning (foreground, background, screen off)
 * - RSSI-based distance detection
 * - Automatic attendance marking (present/left/absent)
 * - API throttling (max 1 call per 20 seconds)
 * - Offline retry queue
 * - Wakelock for screen-off scanning
 * - Method channel communication with Flutter
 */
class BleScanService : Service() {

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "ble_attendance_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START_SCANNING = "START_SCANNING"
        const val ACTION_STOP_SCANNING = "STOP_SCANNING"
        
        // Business logic constants
        const val RSSI_THRESHOLD = -75 // dBm - minimum signal strength for "present"
        const val OUT_OF_RANGE_TIMEOUT = 20000L // 20 seconds
        const val ABSENT_TIMEOUT = 30000L // 30 seconds
        const val API_THROTTLE_INTERVAL = 20000L // 20 seconds between API calls
        
        // Shared preferences keys
        const val PREFS_NAME = "ble_attendance_prefs"
        const val KEY_AUTH_TOKEN = "auth_token"
        const val KEY_STUDENT_ID = "student_id"
        const val KEY_API_BASE_URL = "api_base_url"
        const val KEY_LAST_BEACON_STATE = "last_beacon_state"
        
        var isServiceRunning = false
    }

    private lateinit var bluetoothAdapter: BluetoothAdapter
    private lateinit var bleScanner: BluetoothLeScanner
    private lateinit var notificationManager: NotificationManager
    private lateinit var wakeLock: PowerManager.WakeLock
    private lateinit var httpClient: OkHttpClient
    
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Beacon tracking
    private val detectedBeacons = ConcurrentHashMap<String, BeaconInfo>()
    private var currentPrimaryBeacon: String? = null
    private var lastAttendanceEvent: AttendanceEvent? = null
    private var lastApiCallTime = 0L
    
    // Timers for state management
    private val outOfRangeTimer = ConcurrentHashMap<String, Job>()
    private val absentTimer = ConcurrentHashMap<String, Job>()
    
    // Offline queue
    private val offlineQueue = mutableListOf<AttendanceEvent>()
    
    override fun onCreate() {
        super.onCreate()
        
        // Initialize Bluetooth
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bleScanner = bluetoothAdapter.bluetoothLeScanner
        
        // Initialize notification manager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        
        // Initialize HTTP client
        httpClient = OkHttpClient.Builder()
            .connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .build()
        
        // Acquire wakelock to prevent device sleep during scanning
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "BleScanService::WakeLock"
        )
        
        isServiceRunning = true
        android.util.Log.i("BleScanService", "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_SCANNING -> {
                startForegroundService()
                startBleScanning()
            }
            ACTION_STOP_SCANNING -> {
                stopBleScanning()
                stopSelf()
            }
            else -> {
                startForegroundService()
                startBleScanning()
            }
        }
        
        return START_STICKY // Restart service if killed by system
    }

    private fun startForegroundService() {
        val notification = buildNotification("BLE Attendance Active", "Scanning for beacons...")
        startForeground(NOTIFICATION_ID, notification)
        
        // Acquire wakelock
        if (!wakeLock.isHeld) {
            wakeLock.acquire(10 * 60 * 60 * 1000L) // 10 hours max
            android.util.Log.i("BleScanService", "Wakelock acquired")
        }
    }

    @SuppressLint("MissingPermission")
    private fun startBleScanning() {
        if (!bluetoothAdapter.isEnabled) {
            android.util.Log.w("BleScanService", "Bluetooth is disabled")
            updateNotification("Bluetooth Disabled", "Please enable Bluetooth")
            return
        }
        
        // Configure scan settings for continuous background scanning
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY) // Continuous scanning
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            .setReportDelay(0) // Real-time reporting
            .build()
        
        // Scan for all BLE devices (no filters for maximum compatibility)
        val scanFilters = mutableListOf<ScanFilter>()
        
        try {
            bleScanner.startScan(scanFilters, scanSettings, scanCallback)
            android.util.Log.i("BleScanService", "BLE scanning started")
            updateNotification("Scanning Active", "Searching for classroom beacons...")
            
            // Start periodic beacon cleanup and API retry
            startPeriodicTasks()
        } catch (e: Exception) {
            android.util.Log.e("BleScanService", "Failed to start BLE scan", e)
            updateNotification("Scan Error", "Failed to start BLE scanning")
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBleScanning() {
        try {
            bleScanner.stopScan(scanCallback)
            android.util.Log.i("BleScanService", "BLE scanning stopped")
        } catch (e: Exception) {
            android.util.Log.e("BleScanService", "Error stopping BLE scan", e)
        }
        
        // Release wakelock
        if (wakeLock.isHeld) {
            wakeLock.release()
            android.util.Log.i("BleScanService", "Wakelock released")
        }
        
        // Cancel all timers
        outOfRangeTimer.values.forEach { it.cancel() }
        absentTimer.values.forEach { it.cancel() }
        outOfRangeTimer.clear()
        absentTimer.clear()
        
        serviceScope.cancel()
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            super.onScanResult(callbackType, result)
            processBeaconScan(result)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            super.onBatchScanResults(results)
            results.forEach { processBeaconScan(it) }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            android.util.Log.e("BleScanService", "BLE scan failed with error: $errorCode")
            updateNotification("Scan Failed", "Error code: $errorCode")
        }
    }

    private fun processBeaconScan(result: ScanResult) {
        val device = result.device
        val rssi = result.rssi
        val beaconId = device.address // MAC address as beacon ID
        val beaconName = device.name ?: "Unknown"
        
        val timestamp = System.currentTimeMillis()
        
        // Update beacon info
        val beaconInfo = BeaconInfo(
            id = beaconId,
            name = beaconName,
            rssi = rssi,
            lastSeen = timestamp,
            isInRange = rssi >= RSSI_THRESHOLD
        )
        
        detectedBeacons[beaconId] = beaconInfo
        
        // Cancel absent timer if beacon reappears
        absentTimer[beaconId]?.cancel()
        absentTimer.remove(beaconId)
        
        // Determine primary beacon (closest one)
        updatePrimaryBeacon()
        
        // Process attendance logic
        processAttendanceLogic(beaconInfo)
        
        // Update notification with beacon info
        val closestBeacon = detectedBeacons.values.maxByOrNull { it.rssi }
        if (closestBeacon != null) {
            updateNotification(
                "Beacon Detected",
                "Closest: ${closestBeacon.name} (${closestBeacon.rssi} dBm)"
            )
        }
        
        android.util.Log.d("BleScanService", 
            "Beacon: $beaconId | Name: $beaconName | RSSI: $rssi dBm | In Range: ${beaconInfo.isInRange}")
    }

    private fun updatePrimaryBeacon() {
        // Find the closest beacon (highest RSSI) that is in range
        val closestInRange = detectedBeacons.values
            .filter { it.isInRange }
            .maxByOrNull { it.rssi }
        
        val newPrimaryBeacon = closestInRange?.id
        
        // If primary beacon changed
        if (newPrimaryBeacon != currentPrimaryBeacon) {
            val oldBeacon = currentPrimaryBeacon
            currentPrimaryBeacon = newPrimaryBeacon
            
            android.util.Log.i("BleScanService", 
                "Primary beacon changed: $oldBeacon -> $newPrimaryBeacon")
            
            // If we had a previous beacon and now switched to a new one
            if (oldBeacon != null && newPrimaryBeacon != null) {
                // Mark "left" from old beacon
                markAttendance(oldBeacon, "left")
                // Mark "present" at new beacon
                markAttendance(newPrimaryBeacon, "present")
            } else if (newPrimaryBeacon != null) {
                // First detection
                markAttendance(newPrimaryBeacon, "present")
            }
        }
    }

    private fun processAttendanceLogic(beaconInfo: BeaconInfo) {
        val beaconId = beaconInfo.id
        
        if (beaconInfo.isInRange) {
            // Beacon is in range
            
            // Cancel any pending out-of-range timer
            outOfRangeTimer[beaconId]?.cancel()
            outOfRangeTimer.remove(beaconId)
            
            // If this is the primary beacon and we haven't marked present yet
            if (beaconId == currentPrimaryBeacon) {
                val lastEvent = lastAttendanceEvent
                if (lastEvent == null || lastEvent.beaconId != beaconId || lastEvent.event != "present") {
                    // Mark present
                    markAttendance(beaconId, "present")
                }
            }
        } else {
            // Beacon is detected but RSSI is below threshold (out of range)
            
            // Start out-of-range timer if not already started
            if (!outOfRangeTimer.containsKey(beaconId)) {
                outOfRangeTimer[beaconId] = serviceScope.launch {
                    delay(OUT_OF_RANGE_TIMEOUT)
                    
                    // If still out of range after timeout, mark as "left"
                    val currentBeacon = detectedBeacons[beaconId]
                    if (currentBeacon != null && !currentBeacon.isInRange) {
                        markAttendance(beaconId, "left")
                    }
                    
                    outOfRangeTimer.remove(beaconId)
                }
            }
        }
    }

    private fun startPeriodicTasks() {
        // Periodic beacon cleanup (every 5 seconds)
        serviceScope.launch {
            while (isActive) {
                delay(5000)
                cleanupStaleBeacons()
            }
        }
        
        // Periodic offline queue retry (every 30 seconds)
        serviceScope.launch {
            while (isActive) {
                delay(30000)
                retryOfflineQueue()
            }
        }
    }

    private fun cleanupStaleBeacons() {
        val now = System.currentTimeMillis()
        val staleBeacons = detectedBeacons.filter { (_, beacon) ->
            now - beacon.lastSeen > ABSENT_TIMEOUT
        }
        
        staleBeacons.forEach { (beaconId, _) ->
            // Start absent timer if not already started
            if (!absentTimer.containsKey(beaconId)) {
                absentTimer[beaconId] = serviceScope.launch {
                    delay(ABSENT_TIMEOUT)
                    
                    // Mark as absent if beacon hasn't been seen
                    if (detectedBeacons[beaconId]?.let { now - it.lastSeen > ABSENT_TIMEOUT } == true) {
                        markAttendance(beaconId, "absent")
                        detectedBeacons.remove(beaconId)
                        
                        // If this was the primary beacon, clear it
                        if (currentPrimaryBeacon == beaconId) {
                            currentPrimaryBeacon = null
                            updatePrimaryBeacon()
                        }
                    }
                    
                    absentTimer.remove(beaconId)
                }
            }
        }
    }

    private fun markAttendance(beaconId: String, event: String) {
        val now = System.currentTimeMillis()
        
        // Check API throttling
        if (now - lastApiCallTime < API_THROTTLE_INTERVAL) {
            android.util.Log.i("BleScanService", 
                "API call throttled for beacon $beaconId event $event")
            return
        }
        
        // Check if this is a duplicate event
        if (lastAttendanceEvent?.beaconId == beaconId && lastAttendanceEvent?.event == event) {
            android.util.Log.i("BleScanService", 
                "Duplicate event ignored: $beaconId - $event")
            return
        }
        
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val studentId = prefs.getString(KEY_STUDENT_ID, null)
        val authToken = prefs.getString(KEY_AUTH_TOKEN, null)
        val apiBaseUrl = prefs.getString(KEY_API_BASE_URL, null)
        
        if (studentId == null || authToken == null) {
            android.util.Log.w("BleScanService", "Missing student ID or auth token")
            return
        }
        
        val attendanceEvent = AttendanceEvent(
            studentId = studentId,
            beaconId = beaconId,
            event = event,
            timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date(now))
        )
        
        // Update last event
        lastAttendanceEvent = attendanceEvent
        lastApiCallTime = now
        
        // Save to shared preferences
        prefs.edit().putString(KEY_LAST_BEACON_STATE, "$beaconId:$event:$now").apply()
        
        android.util.Log.i("BleScanService", 
            "🎯 ATTENDANCE EVENT: $studentId at $beaconId -> $event")
        
        // Call API
        sendAttendanceToApi(attendanceEvent, authToken, apiBaseUrl ?: "https://api.example.com")
        
        // Notify Flutter via method channel
        notifyFlutter(attendanceEvent)
    }

    private fun sendAttendanceToApi(
        event: AttendanceEvent,
        authToken: String,
        baseUrl: String
    ) {
        serviceScope.launch {
            try {
                val json = JSONObject().apply {
                    put("student_id", event.studentId)
                    put("beacon_id", event.beaconId)
                    put("event", event.event)
                    put("timestamp", event.timestamp)
                }
                
                val requestBody = json.toString()
                    .toRequestBody("application/json".toMediaType())
                
                val request = Request.Builder()
                    .url("$baseUrl/api/attendance/mark")
                    .addHeader("Authorization", "Bearer $authToken")
                    .addHeader("Content-Type", "application/json")
                    .addHeader("Accept", "application/json")
                    .post(requestBody)
                    .build()
                
                android.util.Log.d("BleScanService", "Sending API request: ${json.toString()}")
                
                httpClient.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val responseBody = response.body?.string() ?: ""
                        android.util.Log.i("BleScanService", 
                            "✅ API call successful: ${response.code} - $responseBody")
                        
                        // Show success notification
                        showAttendanceNotification(
                            "Attendance Marked",
                            "Event: ${event.event} at ${event.beaconId}"
                        )
                    } else {
                        android.util.Log.w("BleScanService", 
                            "⚠️ API call failed: ${response.code} - ${response.message}")
                        
                        // Add to offline queue for retry
                        offlineQueue.add(event)
                    }
                }
            } catch (e: IOException) {
                android.util.Log.e("BleScanService", "❌ Network error", e)
                offlineQueue.add(event)
            } catch (e: Exception) {
                android.util.Log.e("BleScanService", "❌ API call error", e)
                offlineQueue.add(event)
            }
        }
    }

    private fun retryOfflineQueue() {
        if (offlineQueue.isEmpty()) return
        
        android.util.Log.i("BleScanService", "Retrying ${offlineQueue.size} offline events")
        
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val authToken = prefs.getString(KEY_AUTH_TOKEN, null) ?: return
        val apiBaseUrl = prefs.getString(KEY_API_BASE_URL, null) ?: "https://api.example.com"
        
        val eventsToRetry = offlineQueue.toList()
        offlineQueue.clear()
        
        eventsToRetry.forEach { event ->
            sendAttendanceToApi(event, authToken, apiBaseUrl)
        }
    }

    private fun notifyFlutter(event: AttendanceEvent) {
        // Send event to Flutter via method channel
        // This will be picked up by MainActivity
        val intent = Intent("com.smartattendance.app.ATTENDANCE_EVENT")
        intent.putExtra("student_id", event.studentId)
        intent.putExtra("beacon_id", event.beaconId)
        intent.putExtra("event", event.event)
        intent.putExtra("timestamp", event.timestamp)
        sendBroadcast(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "BLE Attendance Scanning",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Continuous BLE beacon scanning for attendance"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, content: String): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(title: String, content: String) {
        val notification = buildNotification(title, content)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun showAttendanceNotification(title: String, content: String) {
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        
        notificationManager.notify((System.currentTimeMillis() % 10000).toInt(), notification)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopBleScanning()
        isServiceRunning = false
        android.util.Log.i("BleScanService", "Service destroyed")
    }

    // Data classes
    data class BeaconInfo(
        val id: String,
        val name: String,
        val rssi: Int,
        val lastSeen: Long,
        val isInRange: Boolean
    )

    data class AttendanceEvent(
        val studentId: String,
        val beaconId: String,
        val event: String, // "present", "left", "absent"
        val timestamp: String
    )
}
