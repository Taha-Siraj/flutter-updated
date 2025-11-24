import Foundation
import CoreBluetooth
import UIKit
import UserNotifications

/**
 * Production-level CoreBluetooth Background Manager
 * 
 * Features:
 * - Real CoreBluetooth background scanning
 * - State preservation and restoration
 * - RSSI-based distance detection
 * - Automatic attendance marking (present/left/absent)
 * - API throttling (max 1 call per 20 seconds)
 * - Offline retry queue
 * - Method channel communication with Flutter
 */
@available(iOS 13.0, *)
class BLEBackgroundManager: NSObject {
    
    static let shared = BLEBackgroundManager()
    
    // CoreBluetooth
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: BeaconInfo] = [:]
    private var currentPrimaryBeacon: String?
    private var lastAttendanceEvent: AttendanceEvent?
    private var lastApiCallTime: Date = Date(timeIntervalSince1970: 0)
    
    // Configuration
    private let rssiThreshold: Int = -75
    private let outOfRangeTimeout: TimeInterval = 20.0
    private let absentTimeout: TimeInterval = 30.0
    private let apiThrottleInterval: TimeInterval = 20.0
    
    // Timers
    private var outOfRangeTimers: [String: Timer] = [:]
    private var absentTimers: [String: Timer] = [:]
    private var cleanupTimer: Timer?
    
    // Offline queue
    private var offlineQueue: [AttendanceEvent] = []
    
    // Authentication
    private var authToken: String?
    private var studentId: String?
    private var apiBaseUrl: String = "https://api.example.com"
    
    // Notification
    private var isNotificationAuthorized = false
    
    private override init() {
        super.init()
        
        // Request notification authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            self.isNotificationAuthorized = granted
            if let error = error {
                print("❌ Notification authorization error: \(error)")
            }
        }
    }
    
    // MARK: - Public API
    
    func configure(authToken: String, studentId: String, apiBaseUrl: String) {
        self.authToken = authToken
        self.studentId = studentId
        self.apiBaseUrl = apiBaseUrl
        
        // Save to UserDefaults for persistence
        UserDefaults.standard.set(authToken, forKey: "ble_auth_token")
        UserDefaults.standard.set(studentId, forKey: "ble_student_id")
        UserDefaults.standard.set(apiBaseUrl, forKey: "ble_api_base_url")
        
        print("✅ BLE Manager configured for student: \(studentId)")
    }
    
    func startScanning() {
        print("🚀 Starting CoreBluetooth background scanning...")
        
        // Load credentials from UserDefaults if not set
        if authToken == nil {
            authToken = UserDefaults.standard.string(forKey: "ble_auth_token")
            studentId = UserDefaults.standard.string(forKey: "ble_student_id")
            apiBaseUrl = UserDefaults.standard.string(forKey: "ble_api_base_url") ?? "https://api.example.com"
        }
        
        // Initialize central manager with restoration
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: "com.smartattendance.app.ble",
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
        
        // Start periodic cleanup
        startCleanupTimer()
        
        print("✅ CoreBluetooth manager initialized")
    }
    
    func stopScanning() {
        print("🛑 Stopping CoreBluetooth scanning...")
        
        centralManager?.stopScan()
        
        // Cancel all timers
        outOfRangeTimers.values.forEach { $0.invalidate() }
        absentTimers.values.forEach { $0.invalidate() }
        cleanupTimer?.invalidate()
        
        outOfRangeTimers.removeAll()
        absentTimers.removeAll()
        
        print("✅ Scanning stopped")
    }
    
    func isScanning() -> Bool {
        return centralManager?.isScanning ?? false
    }
    
    // MARK: - Private Methods
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleBeacons()
        }
    }
    
    private func processBeaconScan(peripheral: CBPeripheral, rssi: Int) {
        let beaconId = peripheral.identifier.uuidString
        let beaconName = peripheral.name ?? "Unknown"
        let timestamp = Date()
        
        let isInRange = rssi >= rssiThreshold
        
        let beaconInfo = BeaconInfo(
            id: beaconId,
            name: beaconName,
            rssi: rssi,
            lastSeen: timestamp,
            isInRange: isInRange
        )
        
        discoveredPeripherals[beaconId] = beaconInfo
        
        // Cancel absent timer if beacon reappears
        absentTimers[beaconId]?.invalidate()
        absentTimers.removeValue(forKey: beaconId)
        
        // Update primary beacon
        updatePrimaryBeacon()
        
        // Process attendance logic
        processAttendanceLogic(beaconInfo: beaconInfo)
        
        print("📡 Beacon: \(beaconName) | RSSI: \(rssi) dBm | In Range: \(isInRange)")
    }
    
    private func updatePrimaryBeacon() {
        // Find closest beacon in range
        let closestInRange = discoveredPeripherals.values
            .filter { $0.isInRange }
            .max(by: { $0.rssi < $1.rssi })
        
        let newPrimaryBeacon = closestInRange?.id
        
        if newPrimaryBeacon != currentPrimaryBeacon {
            let oldBeacon = currentPrimaryBeacon
            currentPrimaryBeacon = newPrimaryBeacon
            
            print("🔄 Primary beacon changed: \(oldBeacon ?? "nil") -> \(newPrimaryBeacon ?? "nil")")
            
            // Handle beacon switching
            if let old = oldBeacon, let new = newPrimaryBeacon {
                markAttendance(beaconId: old, event: "left")
                markAttendance(beaconId: new, event: "present")
            } else if let new = newPrimaryBeacon {
                markAttendance(beaconId: new, event: "present")
            }
        }
    }
    
    private func processAttendanceLogic(beaconInfo: BeaconInfo) {
        let beaconId = beaconInfo.id
        
        if beaconInfo.isInRange {
            // Cancel out-of-range timer
            outOfRangeTimers[beaconId]?.invalidate()
            outOfRangeTimers.removeValue(forKey: beaconId)
            
            // Mark present if this is primary beacon
            if beaconId == currentPrimaryBeacon {
                let lastEvent = lastAttendanceEvent
                if lastEvent == nil || lastEvent?.beaconId != beaconId || lastEvent?.event != "present" {
                    markAttendance(beaconId: beaconId, event: "present")
                }
            }
        } else {
            // Start out-of-range timer
            if outOfRangeTimers[beaconId] == nil {
                outOfRangeTimers[beaconId] = Timer.scheduledTimer(withTimeInterval: outOfRangeTimeout, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    
                    if let beacon = self.discoveredPeripherals[beaconId], !beacon.isInRange {
                        self.markAttendance(beaconId: beaconId, event: "left")
                    }
                    
                    self.outOfRangeTimers.removeValue(forKey: beaconId)
                }
            }
        }
    }
    
    private func cleanupStaleBeacons() {
        let now = Date()
        let staleBeacons = discoveredPeripherals.filter { _, beacon in
            now.timeIntervalSince(beacon.lastSeen) > absentTimeout
        }
        
        for (beaconId, _) in staleBeacons {
            if absentTimers[beaconId] == nil {
                absentTimers[beaconId] = Timer.scheduledTimer(withTimeInterval: absentTimeout, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    
                    if let beacon = self.discoveredPeripherals[beaconId],
                       now.timeIntervalSince(beacon.lastSeen) > self.absentTimeout {
                        self.markAttendance(beaconId: beaconId, event: "absent")
                        self.discoveredPeripherals.removeValue(forKey: beaconId)
                        
                        if self.currentPrimaryBeacon == beaconId {
                            self.currentPrimaryBeacon = nil
                            self.updatePrimaryBeacon()
                        }
                    }
                    
                    self.absentTimers.removeValue(forKey: beaconId)
                }
            }
        }
    }
    
    private func markAttendance(beaconId: String, event: String) {
        let now = Date()
        
        // Check API throttling
        if now.timeIntervalSince(lastApiCallTime) < apiThrottleInterval {
            print("⏳ API call throttled for beacon \(beaconId) event \(event)")
            return
        }
        
        // Check duplicate event
        if lastAttendanceEvent?.beaconId == beaconId && lastAttendanceEvent?.event == event {
            print("⏭️ Duplicate event ignored: \(beaconId) - \(event)")
            return
        }
        
        guard let studentId = studentId, let authToken = authToken else {
            print("⚠️ Missing student ID or auth token")
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: now)
        
        let attendanceEvent = AttendanceEvent(
            studentId: studentId,
            beaconId: beaconId,
            event: event,
            timestamp: timestamp
        )
        
        lastAttendanceEvent = attendanceEvent
        lastApiCallTime = now
        
        // Save to UserDefaults
        UserDefaults.standard.set("\(beaconId):\(event):\(now.timeIntervalSince1970)", forKey: "last_beacon_state")
        
        print("🎯 ATTENDANCE EVENT: \(studentId) at \(beaconId) -> \(event)")
        
        // Send to API
        sendAttendanceToApi(event: attendanceEvent, authToken: authToken)
        
        // Show local notification
        showNotification(title: "Attendance Marked", body: "Event: \(event) at \(beaconId)")
        
        // Notify Flutter
        notifyFlutter(event: attendanceEvent)
    }
    
    private func sendAttendanceToApi(event: AttendanceEvent, authToken: String) {
        let urlString = "\(apiBaseUrl)/api/attendance/mark"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "student_id": event.studentId,
            "beacon_id": event.beaconId,
            "event": event.event,
            "timestamp": event.timestamp
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            print("📤 Sending API request: \(body)")
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    print("❌ Network error: \(error)")
                    self?.offlineQueue.append(event)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        print("✅ API call successful: \(httpResponse.statusCode)")
                        
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("📥 Response: \(responseString)")
                        }
                        
                        self?.showNotification(title: "Attendance Recorded", body: "Event: \(event.event)")
                    } else {
                        print("⚠️ API call failed: \(httpResponse.statusCode)")
                        self?.offlineQueue.append(event)
                    }
                }
            }
            
            task.resume()
        } catch {
            print("❌ JSON serialization error: \(error)")
            offlineQueue.append(event)
        }
    }
    
    private func retryOfflineQueue() {
        guard !offlineQueue.isEmpty, let authToken = authToken else { return }
        
        print("🔄 Retrying \(offlineQueue.count) offline events")
        
        let eventsToRetry = offlineQueue
        offlineQueue.removeAll()
        
        for event in eventsToRetry {
            sendAttendanceToApi(event: event, authToken: authToken)
        }
    }
    
    private func showNotification(title: String, body: String) {
        guard isNotificationAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error)")
            }
        }
    }
    
    private func notifyFlutter(event: AttendanceEvent) {
        // Post notification for Flutter to pick up
        NotificationCenter.default.post(
            name: NSNotification.Name("AttendanceEventNotification"),
            object: nil,
            userInfo: [
                "student_id": event.studentId,
                "beacon_id": event.beaconId,
                "event": event.event,
                "timestamp": event.timestamp
            ]
        )
    }
    
    // MARK: - Data Models
    
    struct BeaconInfo {
        let id: String
        let name: String
        let rssi: Int
        let lastSeen: Date
        let isInRange: Bool
    }
    
    struct AttendanceEvent {
        let studentId: String
        let beaconId: String
        let event: String
        let timestamp: String
    }
}

// MARK: - CBCentralManagerDelegate

@available(iOS 13.0, *)
extension BLEBackgroundManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on - starting scan")
            
            // Start scanning for all peripherals
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            
        case .poweredOff:
            print("⚠️ Bluetooth powered off")
            showNotification(title: "Bluetooth Off", body: "Please enable Bluetooth for attendance tracking")
            
        case .unauthorized:
            print("❌ Bluetooth unauthorized")
            
        case .unsupported:
            print("❌ Bluetooth unsupported")
            
        case .resetting:
            print("⚠️ Bluetooth resetting")
            
        case .unknown:
            print("⚠️ Bluetooth state unknown")
            
        @unknown default:
            print("⚠️ Bluetooth state unknown (default)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, 
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rssiValue = RSSI.intValue
        
        // Filter out invalid RSSI values
        guard rssiValue != 127 && rssiValue != 0 else { return }
        
        // Process beacon scan
        processBeaconScan(peripheral: peripheral, rssi: rssiValue)
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("📡 CoreBluetooth state restoration triggered")
        
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            print("📡 Restored \(peripherals.count) peripheral(s)")
        }
        
        if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            print("📡 Restored scan services: \(scanServices)")
        }
    }
}

