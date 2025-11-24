import Foundation
import BackgroundTasks
import UIKit

@available(iOS 13.0, *)
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    // Background task identifiers
    private let appRefreshTaskIdentifier = "com.smartattendance.app.refresh"
    private let processingTaskIdentifier = "com.smartattendance.app.bleProcessing"
    
    private init() {}
    
    // Register background tasks
    func registerBackgroundTasks() {
        print("📋 Registering background tasks...")
        
        // Register app refresh task (runs every 15 minutes)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        // Register processing task (for longer BLE operations)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskIdentifier,
            using: nil
        ) { task in
            self.handleProcessing(task: task as! BGProcessingTask)
        }
        
        print("✅ Background tasks registered successfully")
    }
    
    // Schedule app refresh task
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshTaskIdentifier)
        
        // Schedule to run in 15 minutes (minimum allowed)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ App refresh task scheduled")
        } catch {
            print("❌ Could not schedule app refresh: \(error)")
        }
    }
    
    // Schedule processing task
    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        
        // Allow device to charge if needed
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        // Schedule to run in 20 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Processing task scheduled")
        } catch {
            print("❌ Could not schedule processing task: \(error)")
        }
    }
    
    // Handle app refresh task
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄 App refresh task started")
        
        // Schedule next refresh
        scheduleAppRefresh()
        
        // Create background task operation
        let operation = BLEScanOperation()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⚠️ App refresh task expired")
            operation.cancel()
        }
        
        // Set completion handler
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
            print("✅ App refresh task completed")
        }
        
        // Start operation
        OperationQueue().addOperation(operation)
    }
    
    // Handle processing task
    private func handleProcessing(task: BGProcessingTask) {
        print("🔄 Processing task started")
        
        // Schedule next processing task
        scheduleProcessing()
        
        // Create background processing operation
        let operation = BLEProcessingOperation()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⚠️ Processing task expired")
            operation.cancel()
        }
        
        // Set completion handler
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
            print("✅ Processing task completed")
        }
        
        // Start operation
        OperationQueue().addOperation(operation)
    }
}

// MARK: - BLE Scan Operation
class BLEScanOperation: Operation {
    @objc private dynamic var _finished = false
    @objc private dynamic var _executing = false
        
    override var isAsynchronous: Bool {
        return true
    }
    
    override var isExecuting: Bool {
        return _executing
    }
    
    override var isFinished: Bool {
        return _finished
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        isExecuting = true
        
        print("📡 BLE scan operation started (placeholder for future implementation)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .background).async {
            Thread.sleep(forTimeInterval: 2.0)
            print("✅ Background BLE scan placeholder completed")
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 25)
        
        guard !isCancelled else {
            print("⚠️ BLE scan operation cancelled")
            self.finish()
            return
        }
        
        print("✅ BLE scan operation completed")
        self.finish()
    }
    
    private func finish() {
        isExecuting = false
        isFinished = true
    }
}

// MARK: - BLE Processing Operation
class BLEProcessingOperation: Operation {
    @objc private dynamic var _finished = false
    @objc private dynamic var _executing = false
    
    override var isAsynchronous: Bool {
        return true
    }
    
    override var isExecuting: Bool {
        return _executing
    }
    
    override var isFinished: Bool {
        return _finished
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        isExecuting = true
        
        print("📡 BLE processing operation started (placeholder for future implementation)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .background).async {
            Thread.sleep(forTimeInterval: 3.0)
            print("✅ Extended BLE processing placeholder completed")
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 25)
        
        guard !isCancelled else {
            print("⚠️ BLE processing operation cancelled")
            self.finish()
            return
        }
        
        print("✅ BLE processing operation completed")
        self.finish()
    }
    
    private func finish() {
        isExecuting = false
        isFinished = true
    }
}
