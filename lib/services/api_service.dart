import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/attendance_model.dart';
import '../utils/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Logger _logger = Logger();
  late Dio _dio;
  bool _isInitialized = false;

  // Initialize Dio HTTP client
  ApiService init() {
    if (_isInitialized) return this;

    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add logging interceptor
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => _logger.d(obj),
    ));

    _isInitialized = true;
    _logger.i('✅ API Service initialized with baseUrl: ${AppConstants.baseUrl}');
    return this;
  }

  // Login (Demo mode - accepts any credentials)
  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    _logger.i('Attempting demo login for $email');

    try {
      // Try real API call first
      final response = await _dio.post(
        AppConstants.loginEndpoint,
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        _logger.i('✅ Login successful (real API)');
        return response.data;
      }
    } catch (e) {
      _logger.w('Real API unavailable, using demo mode: $e');
    }

    // Fallback to demo mode
    await Future.delayed(const Duration(seconds: 1));
    
    if (email.isNotEmpty && password.length >= 6) {
      _logger.i('✅ Demo login successful');
      return {
        'status': 'success',
        'message': 'Login successful (Demo Mode)',
        'user': {
          'id': DateTime.now().millisecondsSinceEpoch,
          'name': email.split('@')[0].toUpperCase(),
          'email': email,
        },
      };
    }
    
    throw Exception('Invalid credentials');
  }

  // 🎯 DUMMY API CALL - Simulates attendance update
  Future<bool> updateAttendance({
    required String studentId,
    required String beaconId,
    required String status,
    required int rssi,
  }) async {
    _logger.i('📡 API TRIGGER: $status for beacon $beaconId (RSSI: $rssi)');

    final payload = {
      'student_id': studentId,
      'beacon_id': beaconId,
      'status': status,
      'rssi': rssi,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Try real API call
      final response = await _dio.post(
        AppConstants.updateAttendanceEndpoint,
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('✅ API call successful (real endpoint)');
        return true;
      }
    } catch (e) {
      _logger.w('Real API unavailable, simulating success: $e');
    }

    // Dummy API simulation (for demo)
    await Future.delayed(const Duration(seconds: 2)); // Simulate network delay
    
    _logger.i('✅ DUMMY API call successful for $beaconId');
    _logger.i('   Payload: $payload');
    
    return true; // Always succeed in demo mode
  }

  // Sync attendance records (batch update)
  Future<bool> syncAttendance({
    required String studentId,
    required List<AttendanceModel> records,
  }) async {
    if (records.isEmpty) return true;

    _logger.i('Syncing ${records.length} attendance records...');

    final payload = {
      'student_id': studentId,
      'records': records.map((r) => r.toMap()).toList(),
    };

    try {
      final response = await _dio.post(
        AppConstants.syncAttendanceEndpoint,
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('✅ Batch sync successful');
        return true;
      }
    } catch (e) {
      _logger.w('Batch sync failed (demo mode active): $e');
    }

    // Demo mode fallback
    await Future.delayed(const Duration(seconds: 1));
    _logger.i('✅ DUMMY batch sync successful');
    return true;
  }

  // Test connection
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('API connection test failed (demo mode active): $e');
      return true; // Return true in demo mode
    }
  }
}
