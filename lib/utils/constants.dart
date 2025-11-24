class AppConstants {
  // API Configuration
  static const String baseUrl = 'https://api.smartattendance.com';
  static const String loginEndpoint = '/login';
  static const String updateAttendanceEndpoint = '/updateAttendance';
  static const String syncAttendanceEndpoint = '/syncAttendance';
  
  // API Timeouts
  static const int connectTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000;
  
  // BLE Configuration
  static const int rssiThreshold = -75; // Signal strength threshold
  static const int scanDuration = 10; // Scan every 10 seconds
  static const Duration scanInterval = Duration(seconds: 10);
  
  // Local Storage Keys
  static const String keyIsLoggedIn = 'isLoggedIn';
  static const String keyStudentId = 'studentId';
  static const String keyStudentName = 'studentName';
  static const String keyEmail = 'email';
  static const String keyPassword = 'password';
  static const String keyEnableBackground = 'enableBackground';
  static const String keyEnableNotifications = 'enableNotifications';
  static const String keyAttendanceRecords = 'attendanceRecords';
  
  // App Info
  static const String appVersion = 'v1.0.0';
  static const String appName = 'Smart Attendance';
  
  // Status
  static const String statusPresent = 'Present';
  static const String statusAbsent = 'Absent';
  
  // BLE Status
  static const String bleScanning = 'Scanning';
  static const String bleConnected = 'Connected';
  static const String bleNotFound = 'Not Found';
  static const String bleDisconnected = 'Disconnected';
}

