import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final Logger _logger = Logger();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.i('🔔 Initializing notification service...');

    try {
      // Android initialization
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization (for future use)
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create Android notification channel for foreground service
      if (Platform.isAndroid) {
        await _createNotificationChannel();
      }

      _isInitialized = true;
      _logger.i('✅ Notification service initialized');
    } catch (e) {
      _logger.e('❌ Notification initialization error: $e');
    }
  }

  // Create Android notification channel
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'attendance_background', // ID
      'Background Scanning', // Name
      description: 'Keeps the app running to scan for BLE beacons',
      importance: Importance.low, // Low importance = no sound
      playSound: false,
      enableVibration: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _logger.i('✅ Android notification channel created');
  }

  // Show foreground service notification (Android)
  Future<void> showForegroundNotification({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'attendance_background',
        'Background Scanning',
        channelDescription: 'Keeps the app running to scan for BLE beacons',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        ongoing: true, // Cannot be dismissed
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        888, // Foreground service notification ID
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      _logger.e('❌ Error showing foreground notification: $e');
    }
  }

  // Show attendance update notification
  Future<void> showAttendanceNotification({
    required String title,
    required String body,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'attendance_updates',
        'Attendance Updates',
        channelDescription: 'Notifications about attendance changes',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000, // Unique ID
        title,
        body,
        notificationDetails,
      );

      _logger.i('📲 Attendance notification shown: $title');
    } catch (e) {
      _logger.e('❌ Error showing attendance notification: $e');
    }
  }

  // Update foreground notification
  Future<void> updateForegroundNotification({
    required String beaconId,
    required int rssi,
    required String status,
  }) async {
    await showForegroundNotification(
      title: 'Smart Attendance Active',
      body: 'Beacon: $beaconId | RSSI: $rssi dBm | $status',
    );
  }

  // Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  // Notification tap handler
  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('Notification tapped: ${response.payload}');
    // Handle navigation if needed
  }
}

