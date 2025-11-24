import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import '../models/attendance_model.dart';
import '../services/ble_service.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';
import '../services/background_service.dart';
import '../utils/constants.dart';

class AttendanceProvider with ChangeNotifier {
  final Logger _logger = Logger();
  final BleService _bleService = BleService();
  final ApiService _apiService = ApiService().init();
  final LocalStorageService _localStorage = LocalStorageService();
  final BackgroundService _backgroundService = BackgroundService();

  // Set context for BLE dialogs
  void setContext(BuildContext context) {
    _bleService.setContext(context);
  }

  // State variables
  List<AttendanceModel> _attendanceRecords = [];
  String _bleStatus = AppConstants.bleNotFound;
  String _beaconId = 'N/A';
  int _rssi = 0;
  DateTime _lastUpdated = DateTime.now();
  bool _isScanning = false;
  bool _isInitialized = false;

  // Previous state for change detection
  String _previousStatus = '';
  String _previousBeaconId = '';

  // Auto-sync timer
  Timer? _autoSyncTimer;
  Timer? _attendanceCheckTimer;

  // Getters
  List<AttendanceModel> get attendanceRecords => _attendanceRecords;
  String get bleStatus => _bleStatus;
  String get beaconId => _beaconId;
  int get rssi => _rssi;
  DateTime get lastUpdated => _lastUpdated;
  bool get isScanning => _isScanning;
  bool get isInitialized => _isInitialized;

  List<AttendanceModel> get unsyncedRecords =>
      _attendanceRecords.where((r) => !r.synced).toList();

  // Initialize provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _localStorage.init();
      await _bleService.initialize();

      // Load saved attendance records
      _attendanceRecords = _localStorage.getAttendanceRecords();
      _logger.i('Loaded ${_attendanceRecords.length} attendance records');

      // Listen to BLE streams
      _bleService.statusStream.listen(_onBleStatusChanged);
      _bleService.beaconIdStream.listen(_onBeaconIdChanged);
      _bleService.rssiStream.listen(_onRssiChanged);

      // Start auto-sync timer (every 5 minutes)
      _startAutoSync();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _logger.e('Provider initialization error: $e');
    }
  }

  // BLE status changed
  void _onBleStatusChanged(String status) {
    _bleStatus = status;
    _lastUpdated = DateTime.now();
    
    // Check for attendance change
    if (_previousStatus != status) {
      _checkAndMarkAttendance();
      _previousStatus = status;
    }
    
    notifyListeners();
  }

  // Beacon ID changed
  void _onBeaconIdChanged(String beaconId) {
    if (_beaconId != beaconId) {
      _beaconId = beaconId;
      _lastUpdated = DateTime.now();
      
      // New beacon detected, check attendance
      if (_previousBeaconId != beaconId) {
        _checkAndMarkAttendance();
        _previousBeaconId = beaconId;
      }
      
      notifyListeners();
    }
  }

  // RSSI changed
  void _onRssiChanged(int rssi) {
    _rssi = rssi;
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  // Start BLE scanning
  Future<void> startScanning() async {
    try {
      await _bleService.startScanning();
      _isScanning = true;
      
      // Start background service for Android
      await _backgroundService.startService();
      
      // Start periodic attendance checking
      _attendanceCheckTimer = Timer.periodic(
        AppConstants.scanInterval,
        (_) => _checkAndMarkAttendance(),
      );
      
      notifyListeners();
      _logger.i('✅ Started attendance scanning with background service');
    } catch (e) {
      _logger.e('❌ Error starting scan: $e');
    }
  }

  // Stop BLE scanning
  Future<void> stopScanning() async {
    try {
      await _bleService.stopScanning();
      await _backgroundService.stopService();
      _isScanning = false;
      _attendanceCheckTimer?.cancel();
      notifyListeners();
      _logger.i('🛑 Stopped attendance scanning and background service');
    } catch (e) {
      _logger.e('❌ Error stopping scan: $e');
    }
  }

  // Check if background service is running
  Future<bool> isBackgroundServiceRunning() async {
    return await _backgroundService.isServiceRunning();
  }

  // Check and mark attendance based on BLE status
  void _checkAndMarkAttendance() {
    if (!_isScanning || _beaconId == 'N/A') return;

    final String status = _bleService.isInRange()
        ? AppConstants.statusPresent
        : AppConstants.statusAbsent;

    // Create new attendance record
    final newRecord = AttendanceModel(
      id: DateTime.now().millisecondsSinceEpoch,
      date: _formatDate(DateTime.now()),
      time: _formatTime(DateTime.now()),
      beaconId: _beaconId,
      rssi: _rssi,
      status: status,
      synced: false,
    );

    // Add to list and save
    _attendanceRecords.insert(0, newRecord);
    _localStorage.addAttendanceRecord(newRecord);

    // Try to sync with API
    _syncSingleRecord(newRecord);

    notifyListeners();
    _logger.i('Marked attendance: $status for $beaconId');
  }

  // Sync single record with API
  Future<void> _syncSingleRecord(AttendanceModel record) async {
    try {
      final studentId = _localStorage.getStudentId();
      final success = await _apiService.updateAttendance(
        studentId: studentId,
        beaconId: record.beaconId,
        status: record.status,
        rssi: record.rssi,
      );

      if (success) {
        // Mark as synced
        final updatedRecord = record.copyWith(synced: true);
        final index = _attendanceRecords.indexWhere((r) => r.id == record.id);
        if (index != -1) {
          _attendanceRecords[index] = updatedRecord;
          await _localStorage.updateAttendanceRecord(updatedRecord);
          notifyListeners();
        }
      }
    } catch (e) {
      _logger.w('Failed to sync record: $e');
      // Will be synced later by auto-sync
    }
  }

  // Manually sync all unsynced records
  Future<bool> syncAllRecords() async {
    try {
      final unsynced = unsyncedRecords;
      if (unsynced.isEmpty) {
        _logger.i('No records to sync');
        return true;
      }

      final studentId = _localStorage.getStudentId();
      final success = await _apiService.syncAttendance(
        studentId: studentId,
        records: unsynced,
      );

      if (success) {
        // Mark all as synced
        final recordIds = unsynced.map((r) => r.id).toList();
        await _localStorage.markRecordsAsSynced(recordIds);
        
        // Reload records
        _attendanceRecords = _localStorage.getAttendanceRecords();
        notifyListeners();
        
        _logger.i('Synced ${unsynced.length} records');
        return true;
      }
    } catch (e) {
      _logger.e('Sync failed: $e');
    }
    return false;
  }

  // Auto-sync timer
  void _startAutoSync() {
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (unsyncedRecords.isNotEmpty) {
        _logger.i('Auto-syncing ${unsyncedRecords.length} records');
        await syncAllRecords();
      }
    });
  }

  // Filter records by date
  List<AttendanceModel> getRecordsByDate(DateTime date) {
    final dateStr = _formatDate(date);
    return _attendanceRecords.where((r) => r.date == dateStr).toList();
  }

  // Get records for date range
  List<AttendanceModel> getRecordsInRange(DateTime start, DateTime end) {
    return _attendanceRecords.where((r) {
      final recordDate = DateTime.parse(r.date);
      return recordDate.isAfter(start.subtract(const Duration(days: 1))) &&
             recordDate.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  // Helper methods
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  // Refresh data
  Future<void> refresh() async {
    _attendanceRecords = _localStorage.getAttendanceRecords();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _attendanceCheckTimer?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}

