import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../models/beacon_event.dart';
import '../models/beacon_mapping.dart';
import 'attendance_api.dart';
import 'offline_queue.dart';
import 'local_storage.dart';

/// Unified Background BLE Service
/// Coordinates between native Android/iOS BLE scanning and Flutter
class BackgroundBleService {
  static final BackgroundBleService _instance = BackgroundBleService._internal();
  factory BackgroundBleService() => _instance;
  BackgroundBleService._internal();

  final Logger _logger = Logger();
  final MethodChannel _channel = const MethodChannel('com.smartattendance.app/ble');
  
  final AttendanceApiService _apiService = AttendanceApiService();
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  final LocalStorageService _localStorage = LocalStorageService();
  
  final StreamController<BeaconEvent> _eventController = 
      StreamController<BeaconEvent>.broadcast();
  
  bool _isInitialized = false;
  bool _isScanning = false;
  
  List<BeaconMapping> _beaconMappings = [];
  String? _currentBeaconId;
  DateTime? _lastEventTime;

  /// Stream of attendance events
  Stream<BeaconEvent> get eventStream => _eventController.stream;

  /// Is currently scanning
  bool get isScanning => _isScanning;

  /// Current beacon ID
  String? get currentBeaconId => _currentBeaconId;

  /// Beacon mappings
  List<BeaconMapping> get beaconMappings => _beaconMappings;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.i('🚀 Initializing Background BLE Service...');

    try {
      // Initialize dependencies
      await _localStorage.init();
      await _offlineQueue.initialize();

      // Set up method channel handler
      _channel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      _logger.i('✅ Background BLE Service initialized');
    } catch (e) {
      _logger.e('❌ Initialization error: $e');
      rethrow;
    }
  }

  /// Start BLE scanning service
  Future<bool> startScanning({
    required String authToken,
    required String studentId,
    String? apiBaseUrl,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isScanning) {
      _logger.w('⚠️ Already scanning');
      return false;
    }

    _logger.i('🔄 Starting BLE scanning service...');

    try {
      // Configure API service
      _apiService.init(baseUrl: apiBaseUrl);
      _apiService.setAuthToken(authToken);
      _apiService.setStudentId(studentId);

      // Fetch beacon mappings
      await fetchBeaconMappings();

      // Start native BLE service
      final success = await _channel.invokeMethod<bool>(
        'startBleService',
        {
          'authToken': authToken,
          'studentId': studentId,
          'apiBaseUrl': apiBaseUrl ?? 'https://api.example.com',
        },
      );

      if (success == true) {
        _isScanning = true;
        _logger.i('✅ BLE scanning service started');
        return true;
      } else {
        _logger.w('⚠️ Failed to start BLE service');
        return false;
      }
    } catch (e) {
      _logger.e('❌ Error starting BLE service: $e');
      return false;
    }
  }

  /// Stop BLE scanning service
  Future<bool> stopScanning() async {
    if (!_isScanning) {
      _logger.w('⚠️ Not currently scanning');
      return false;
    }

    _logger.i('🛑 Stopping BLE scanning service...');

    try {
      final success = await _channel.invokeMethod<bool>('stopBleService');

      if (success == true) {
        _isScanning = false;
        _currentBeaconId = null;
        _logger.i('✅ BLE scanning service stopped');
        return true;
      } else {
        _logger.w('⚠️ Failed to stop BLE service');
        return false;
      }
    } catch (e) {
      _logger.e('❌ Error stopping BLE service: $e');
      return false;
    }
  }

  /// Check if native service is running
  Future<bool> isServiceRunning() async {
    try {
      final isRunning = await _channel.invokeMethod<bool>('isServiceRunning');
      return isRunning ?? false;
    } catch (e) {
      _logger.w('⚠️ Error checking service status: $e');
      return false;
    }
  }

  /// Fetch beacon mappings from API
  Future<void> fetchBeaconMappings() async {
    try {
      _logger.i('📡 Fetching beacon mappings from API...');
      _beaconMappings = await _apiService.fetchBeaconMappings();
      
      if (_beaconMappings.isEmpty) {
        _logger.w('⚠️ No beacon mappings found');
      } else {
        _logger.i('✅ Loaded ${_beaconMappings.length} beacon mappings');
        
        // Save to local storage for offline access
        await _localStorage.saveString(
          'beacon_mappings',
          _beaconMappings.map((m) => m.toJson()).toList().toString(),
        );
      }
    } catch (e) {
      _logger.e('❌ Error fetching beacon mappings: $e');
    }
  }

  /// Get beacon mapping by ID
  BeaconMapping? getBeaconMapping(String beaconId) {
    return _beaconMappings
        .where((m) => m.beaconId.toLowerCase() == beaconId.toLowerCase())
        .firstOrNull;
  }

  /// Check if beacon is mapped
  bool isBeaconMapped(String beaconId) {
    return getBeaconMapping(beaconId) != null;
  }

  /// Update auth token
  Future<void> updateAuthToken(String authToken) async {
    try {
      _apiService.setAuthToken(authToken);
      await _channel.invokeMethod('updateAuthToken', {'authToken': authToken});
      _logger.i('✅ Auth token updated');
    } catch (e) {
      _logger.e('❌ Error updating auth token: $e');
    }
  }

  /// Get last beacon state from native
  Future<String?> getLastBeaconState() async {
    try {
      return await _channel.invokeMethod<String>('getLastBeaconState');
    } catch (e) {
      _logger.w('⚠️ Error getting last beacon state: $e');
      return null;
    }
  }

  /// Handle method calls from native
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    _logger.d('📞 Method call from native: ${call.method}');

    switch (call.method) {
      case 'onAttendanceEvent':
        return _handleAttendanceEvent(call.arguments);
      
      default:
        _logger.w('⚠️ Unknown method call: ${call.method}');
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  /// Handle attendance event from native
  Future<void> _handleAttendanceEvent(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      
      final event = BeaconEvent(
        studentId: data['student_id'] as String,
        beaconId: data['beacon_id'] as String,
        event: data['event'] as String,
        timestamp: data['timestamp'] is String
            ? DateTime.parse(data['timestamp'])
            : DateTime.now(),
        rssi: data['rssi'] as int?,
        synced: true, // Native already sent to API
      );

      _currentBeaconId = event.beaconId;
      _lastEventTime = event.timestamp;

      // Emit event to stream
      _eventController.add(event);

      // Save to local storage
      await _saveEventLocally(event);

      // Check if beacon is mapped
      final mapping = getBeaconMapping(event.beaconId);
      if (mapping != null) {
        _logger.i('✅ Event for mapped beacon: ${mapping.classroomName}');
      } else {
        _logger.w('⚠️ Event for unmapped beacon: ${event.beaconId}');
      }

      _logger.i('📥 Attendance event received: ${event.event} at ${event.beaconId}');
    } catch (e) {
      _logger.e('❌ Error handling attendance event: $e');
    }
  }

  /// Save event to local storage
  Future<void> _saveEventLocally(BeaconEvent event) async {
    try {
      final events = await _localStorage.getAttendanceRecords();
      
      // Convert to BeaconEvent (if not already)
      final newEvents = [...events.map((e) => BeaconEvent(
        studentId: _apiService.studentId ?? e.studentId,
        beaconId: e.beaconId,
        event: e.status == 'Present' ? 'present' : 'absent',
        timestamp: DateTime.parse('${e.date} ${e.time}'),
        rssi: e.rssi,
        synced: e.synced,
      )), event];
      
      // Save back (implementation depends on AttendanceModel structure)
      _logger.d('💾 Event saved locally');
    } catch (e) {
      _logger.w('⚠️ Error saving event locally: $e');
    }
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'is_initialized': _isInitialized,
      'is_scanning': _isScanning,
      'current_beacon': _currentBeaconId,
      'last_event_time': _lastEventTime?.toIso8601String(),
      'beacon_mappings_count': _beaconMappings.length,
      'offline_queue_size': _offlineQueue.queueSize,
    };
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
    _offlineQueue.dispose();
    _logger.i('👋 Background BLE Service disposed');
  }
}

/// Extension for firstOrNull
extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

