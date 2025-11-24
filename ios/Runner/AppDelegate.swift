import Flutter
import UIKit
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // ⭐ Setup Method Channel for BLE control
    let bleChannel = FlutterMethodChannel(
      name: "com.smartattendance.app/ble",
      binaryMessenger: controller.binaryMessenger
    )
    
    bleChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      self?.handleMethodCall(call: call, result: result)
    })
    
    GeneratedPluginRegistrant.register(with: self)
    
    // ⭐ Handle Bluetooth background restoration
    if launchOptions?[UIApplication.LaunchOptionsKey.bluetoothCentrals] != nil {
      print("📡 App launched for Bluetooth background event")
      if #available(iOS 13.0, *) {
        BLEBackgroundManager.shared.startScanning()
      }
    }
    
    // Register background tasks (iOS 13+)
    if #available(iOS 13.0, *) {
      BackgroundTaskManager.shared.registerBackgroundTasks()
      print("✅ Background tasks registered")
    }
    
    // Listen for attendance events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAttendanceEvent(_:)),
      name: NSNotification.Name("AttendanceEventNotification"),
      object: nil
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @objc func handleAttendanceEvent(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let studentId = userInfo["student_id"] as? String,
          let beaconId = userInfo["beacon_id"] as? String,
          let event = userInfo["event"] as? String,
          let timestamp = userInfo["timestamp"] as? String else {
      return
    }
    
    // Send to Flutter
    let controller = window?.rootViewController as? FlutterViewController
    let bleChannel = FlutterMethodChannel(
      name: "com.smartattendance.app/ble",
      binaryMessenger: controller!.binaryMessenger
    )
    
    bleChannel.invokeMethod("onAttendanceEvent", arguments: [
      "student_id": studentId,
      "beacon_id": beaconId,
      "event": event,
      "timestamp": timestamp
    ])
    
    print("📤 Sent attendance event to Flutter: \(event) at \(beaconId)")
  }
  
  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(FlutterError(code: "UNAVAILABLE", message: "iOS 13+ required", details: nil))
      return
    }
    
    switch call.method {
    case "startBleService":
      guard let args = call.arguments as? [String: Any],
            let authToken = args["authToken"] as? String,
            let studentId = args["studentId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing authToken or studentId", details: nil))
        return
      }
      
      let apiBaseUrl = args["apiBaseUrl"] as? String ?? "https://api.example.com"
      
      BLEBackgroundManager.shared.configure(
        authToken: authToken,
        studentId: studentId,
        apiBaseUrl: apiBaseUrl
      )
      BLEBackgroundManager.shared.startScanning()
      
      print("✅ iOS BLE service started")
      result(true)
      
    case "stopBleService":
      BLEBackgroundManager.shared.stopScanning()
      print("🛑 iOS BLE service stopped")
      result(true)
      
    case "isServiceRunning":
      let isRunning = BLEBackgroundManager.shared.isScanning()
      result(isRunning)
      
    case "updateAuthToken":
      guard let args = call.arguments as? [String: Any],
            let authToken = args["authToken"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing authToken", details: nil))
        return
      }
      
      UserDefaults.standard.set(authToken, forKey: "ble_auth_token")
      result(true)
      
    case "getLastBeaconState":
      let lastState = UserDefaults.standard.string(forKey: "last_beacon_state")
      result(lastState)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  // Handle app entering background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    print("📱 App entered background - BLE scanning continues")
    
    // Schedule background refresh task
    if #available(iOS 13.0, *) {
      BackgroundTaskManager.shared.scheduleAppRefresh()
    }
  }
  
  // Handle app becoming active
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    print("📱 App became active")
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

