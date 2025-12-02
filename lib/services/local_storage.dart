import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../models/attendance_model.dart';
import '../utils/constants.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  final Logger _logger = Logger();
  SharedPreferences? _prefs;

  // Initialize SharedPreferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Login related methods
  Future<void> saveLoginCredentials({
    required String studentId,
    required String studentName,
    required String email,
    String? password,
  }) async {
    await init();
    await _prefs?.setBool(AppConstants.keyIsLoggedIn, true);
    await _prefs?.setString(AppConstants.keyStudentId, studentId);
    await _prefs?.setString(AppConstants.keyStudentName, studentName);
    await _prefs?.setString(AppConstants.keyEmail, email);
    if (password != null) {
      await _prefs?.setString(AppConstants.keyPassword, password);
    }
    _logger.i('Login credentials saved');
  }

  // Verify login credentials
  Future<bool> verifyLogin({
    required String email,
    required String password,
  }) async {
    await init();
    final storedEmail = _prefs?.getString(AppConstants.keyEmail) ?? '';
    final storedPassword = _prefs?.getString(AppConstants.keyPassword) ?? '';
    
    return storedEmail == email && storedPassword == password;
  }

  // Check if user exists
  Future<bool> userExists(String email) async {
    await init();
    final storedEmail = _prefs?.getString(AppConstants.keyEmail) ?? '';
    return storedEmail.isNotEmpty && storedEmail == email;
  }

  bool isLoggedIn() {
    return _prefs?.getBool(AppConstants.keyIsLoggedIn) ?? false;
  }

  String getStudentName() {
    return _prefs?.getString(AppConstants.keyStudentName) ?? 'Student';
  }

  String getStudentId() {
    return _prefs?.getString(AppConstants.keyStudentId) ?? '';
  }

  String getEmail() {
    return _prefs?.getString(AppConstants.keyEmail) ?? '';
  }

  Future<void> logout() async {
    await init();
    await _prefs?.clear();
    _logger.i('Logged out and cleared storage');
  }

  // Settings related methods
  Future<void> setBackgroundScanningEnabled(bool enabled) async {
    await init();
    await _prefs?.setBool(AppConstants.keyEnableBackground, enabled);
    _logger.i('Background scanning: $enabled');
  }

  bool isBackgroundScanningEnabled() {
    return _prefs?.getBool(AppConstants.keyEnableBackground) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await init();
    await _prefs?.setBool(AppConstants.keyEnableNotifications, enabled);
    _logger.i('Notifications: $enabled');
  }

  bool isNotificationsEnabled() {
    return _prefs?.getBool(AppConstants.keyEnableNotifications) ?? true;
  }

  // Attendance records methods
  Future<void> saveAttendanceRecords(List<AttendanceModel> records) async {
    await init();
    final List<String> jsonList =
        records.map((record) => record.toJson()).toList();
    await _prefs?.setStringList(AppConstants.keyAttendanceRecords, jsonList);
    _logger.i('Saved ${records.length} attendance records');
  }

  List<AttendanceModel> getAttendanceRecords() {
    final List<String>? jsonList =
        _prefs?.getStringList(AppConstants.keyAttendanceRecords);
    if (jsonList == null || jsonList.isEmpty) {
      return [];
    }
    return jsonList
        .map((json) => AttendanceModel.fromJson(json))
        .toList();
  }

  Future<void> addAttendanceRecord(AttendanceModel record) async {
    final records = getAttendanceRecords();
    records.add(record);
    await saveAttendanceRecords(records);
    _logger.i('Added attendance record: ${record.beaconId}');
  }

  Future<void> updateAttendanceRecord(AttendanceModel updatedRecord) async {
    final records = getAttendanceRecords();
    final index = records.indexWhere((r) => r.id == updatedRecord.id);
    if (index != -1) {
      records[index] = updatedRecord;
      await saveAttendanceRecords(records);
      _logger.i('Updated attendance record: ${updatedRecord.id}');
    }
  }

  Future<void> markRecordsAsSynced(List<int> recordIds) async {
    final records = getAttendanceRecords();
    for (var id in recordIds) {
      final index = records.indexWhere((r) => r.id == id);
      if (index != -1) {
        records[index] = records[index].copyWith(synced: true);
      }
    }
    await saveAttendanceRecords(records);
    _logger.i('Marked ${recordIds.length} records as synced');
  }

  List<AttendanceModel> getUnsyncedRecords() {
    return getAttendanceRecords().where((r) => !r.synced).toList();
  }

  // Generic string storage methods
  Future<void> saveString(String key, String value) async {
    await init();
    await _prefs?.setString(key, value);
    _logger.i('Saved string: $key');
  }

  Future<String?> getString(String key) async {
    await init();
    return _prefs?.getString(key);
  }

  // Clear all stored data
  Future<void> clearAll() async {
    await init();
    await _prefs?.clear();
    _logger.i('Cleared all storage');
  }
}

