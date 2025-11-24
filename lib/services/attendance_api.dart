import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/beacon_event.dart';
import '../models/beacon_mapping.dart';
import 'local_storage.dart';

/// Real API integration service for Laravel backend
class AttendanceApiService {
  static final AttendanceApiService _instance = AttendanceApiService._internal();
  factory AttendanceApiService() => _instance;
  AttendanceApiService._internal();

  final Logger _logger = Logger();
  late Dio _dio;
  bool _isInitialized = false;

  String? _authToken;
  String? _studentId;
  String _baseUrl = 'https://api.example.com'; // Configure this

  /// Initialize API service
  AttendanceApiService init({String? baseUrl}) {
    if (_isInitialized) return this;

    _baseUrl = baseUrl ?? _baseUrl;

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => _logger.d(obj),
    ));

    // Add auth token interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_authToken != null) {
          options.headers['Authorization'] = 'Bearer $_authToken';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          _logger.w('⚠️ Unauthorized - token may be expired');
          // Handle token refresh here if needed
        }
        return handler.next(error);
      },
    ));

    _isInitialized = true;
    _logger.i('✅ API Service initialized with baseUrl: $_baseUrl');
    return this;
  }

  /// Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
    _logger.i('✅ Auth token updated');
  }

  /// Set student ID
  void setStudentId(String studentId) {
    _studentId = studentId;
    _logger.i('✅ Student ID set: $studentId');
  }

  /// Login with email and password
  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    try {
      _logger.i('📡 Attempting login for: $email');

      final response = await _dio.post(
        '/api/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        
        // Extract token and student info
        if (data['token'] != null) {
          _authToken = data['token'];
          _studentId = data['user']?['id']?.toString() ?? data['student_id']?.toString();
          
          // Save to local storage
          final localStorage = LocalStorageService();
          await localStorage.init();
          await localStorage.saveString('auth_token', _authToken!);
          if (_studentId != null) {
            await localStorage.saveString('student_id', _studentId!);
          }
          
          _logger.i('✅ Login successful - Token saved');
          return data;
        }
      }

      return null;
    } on DioException catch (e) {
      _logger.e('❌ Login error: ${e.message}');
      if (e.response != null) {
        _logger.e('Response data: ${e.response?.data}');
      }
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      _logger.e('❌ Unexpected login error: $e');
      rethrow;
    }
  }

  /// Fetch beacon mappings for the student
  Future<List<BeaconMapping>> fetchBeaconMappings() async {
    try {
      _logger.i('📡 Fetching beacon mappings...');

      final response = await _dio.get('/api/beacons/mappings');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['beacons'] ?? response.data;
        final mappings = data.map((json) => BeaconMapping.fromJson(json)).toList();
        
        _logger.i('✅ Fetched ${mappings.length} beacon mappings');
        return mappings;
      }

      return [];
    } on DioException catch (e) {
      _logger.e('❌ Error fetching beacon mappings: ${e.message}');
      return [];
    } catch (e) {
      _logger.e('❌ Unexpected error fetching mappings: $e');
      return [];
    }
  }

  /// Mark attendance (production API call)
  Future<bool> markAttendance(BeaconEvent event) async {
    try {
      _logger.i('🎯 Marking attendance: ${event.event} at ${event.beaconId}');

      final response = await _dio.post(
        '/api/attendance/mark',
        data: event.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('✅ Attendance marked successfully');
        _logger.d('Response: ${response.data}');
        return true;
      }

      _logger.w('⚠️ Unexpected status code: ${response.statusCode}');
      return false;
    } on DioException catch (e) {
      _logger.e('❌ Error marking attendance: ${e.message}');
      if (e.response != null) {
        _logger.e('Response: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      _logger.e('❌ Unexpected error marking attendance: $e');
      return false;
    }
  }

  /// Batch sync multiple attendance events
  Future<Map<String, dynamic>> syncAttendanceBatch(
    List<BeaconEvent> events,
  ) async {
    try {
      _logger.i('📡 Syncing ${events.length} attendance events...');

      final response = await _dio.post(
        '/api/attendance/sync',
        data: {
          'student_id': _studentId,
          'events': events.map((e) => e.toJson()).toList(),
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final successCount = data['success_count'] ?? events.length;
        final failedCount = data['failed_count'] ?? 0;
        
        _logger.i('✅ Batch sync complete: $successCount success, $failedCount failed');
        
        return {
          'success': true,
          'success_count': successCount,
          'failed_count': failedCount,
        };
      }

      return {'success': false, 'success_count': 0, 'failed_count': events.length};
    } on DioException catch (e) {
      _logger.e('❌ Batch sync error: ${e.message}');
      return {'success': false, 'success_count': 0, 'failed_count': events.length};
    } catch (e) {
      _logger.e('❌ Unexpected batch sync error: $e');
      return {'success': false, 'success_count': 0, 'failed_count': events.length};
    }
  }

  /// Fetch attendance history
  Future<List<BeaconEvent>> fetchAttendanceHistory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      _logger.i('📡 Fetching attendance history...');

      final Map<String, dynamic> queryParams = {};
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final response = await _dio.get(
        '/api/attendance/history',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['attendance'] ?? response.data;
        final events = data.map((json) => BeaconEvent.fromJson(json)).toList();
        
        _logger.i('✅ Fetched ${events.length} attendance records');
        return events;
      }

      return [];
    } on DioException catch (e) {
      _logger.e('❌ Error fetching history: ${e.message}');
      return [];
    } catch (e) {
      _logger.e('❌ Unexpected error fetching history: $e');
      return [];
    }
  }

  /// Check API connectivity
  Future<bool> checkConnectivity() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('⚠️ API connectivity check failed: $e');
      return false;
    }
  }

  /// Refresh auth token (if backend supports it)
  Future<String?> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        '/api/refresh-token',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        if (newToken != null) {
          _authToken = newToken;
          
          // Save to local storage
          final localStorage = LocalStorageService();
          await localStorage.init();
          await localStorage.saveString('auth_token', newToken);
          
          _logger.i('✅ Token refreshed');
          return newToken;
        }
      }

      return null;
    } catch (e) {
      _logger.e('❌ Token refresh error: $e');
      return null;
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _dio.post('/api/logout');
      _logger.i('✅ Logout successful');
    } catch (e) {
      _logger.w('⚠️ Logout error: $e');
    } finally {
      // Clear local auth data
      _authToken = null;
      _studentId = null;
      
      final localStorage = LocalStorageService();
      await localStorage.init();
      await localStorage.clearAll();
    }
  }

  /// Get base URL
  String get baseUrl => _baseUrl;

  /// Get student ID
  String? get studentId => _studentId;

  /// Get auth token
  String? get authToken => _authToken;

  /// Check if authenticated
  bool get isAuthenticated => _authToken != null && _studentId != null;
}

