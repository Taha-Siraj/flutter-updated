import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../models/beacon_event.dart';
import 'attendance_api.dart';

/// Offline queue for attendance events
/// Stores events locally when API is unavailable and retries when online
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  final Logger _logger = Logger();
  final AttendanceApiService _apiService = AttendanceApiService();
  
  static const String _queueKey = 'offline_attendance_queue';
  static const int _maxQueueSize = 100;
  static const Duration _retryInterval = Duration(minutes: 5);
  
  List<BeaconEvent> _queue = [];
  Timer? _retryTimer;
  bool _isProcessing = false;

  /// Initialize the offline queue
  Future<void> initialize() async {
    await _loadQueue();
    _startRetryTimer();
    _logger.i('✅ Offline queue initialized with ${_queue.length} events');
  }

  /// Add event to offline queue
  Future<void> addEvent(BeaconEvent event) async {
    // Mark as unsynced
    final unsyncedEvent = event.copyWith(synced: false);
    
    // Add to queue
    _queue.add(unsyncedEvent);
    
    // Limit queue size
    if (_queue.length > _maxQueueSize) {
      _queue.removeAt(0); // Remove oldest
      _logger.w('⚠️ Queue size exceeded, removed oldest event');
    }
    
    await _saveQueue();
    _logger.i('📥 Added event to offline queue (${_queue.length} total)');
    
    // Try to process immediately
    _processQueue();
  }

  /// Get all queued events
  List<BeaconEvent> getQueuedEvents() {
    return List.unmodifiable(_queue);
  }

  /// Get queue size
  int get queueSize => _queue.length;

  /// Check if queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Process the offline queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    
    _isProcessing = true;
    _logger.i('🔄 Processing offline queue (${_queue.length} events)...');
    
    try {
      // Check API connectivity first
      final isConnected = await _apiService.checkConnectivity();
      if (!isConnected) {
        _logger.w('⚠️ API not reachable, will retry later');
        _isProcessing = false;
        return;
      }
      
      // Process events in batch if supported, otherwise one by one
      final eventsToProcess = List<BeaconEvent>.from(_queue);
      int successCount = 0;
      int failCount = 0;
      
      // Try batch sync first (more efficient)
      if (eventsToProcess.length > 5) {
        try {
          final result = await _apiService.syncAttendanceBatch(eventsToProcess);
          if (result['success'] == true) {
            successCount = result['success_count'] ?? 0;
            failCount = result['failed_count'] ?? 0;
            
            // Remove successful events from queue
            _queue.removeRange(0, successCount);
            await _saveQueue();
            
            _logger.i('✅ Batch sync: $successCount success, $failCount failed');
          }
        } catch (e) {
          _logger.w('⚠️ Batch sync failed, falling back to individual: $e');
          // Fall through to individual processing
        }
      }
      
      // Process remaining events individually
      final remaining = List<BeaconEvent>.from(_queue);
      for (var event in remaining) {
        try {
          final success = await _apiService.markAttendance(event);
          if (success) {
            _queue.remove(event);
            successCount++;
            await _saveQueue();
          } else {
            failCount++;
          }
          
          // Small delay between requests
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          _logger.w('⚠️ Error processing event: $e');
          failCount++;
        }
      }
      
      _logger.i('✅ Queue processing complete: $successCount synced, ${_queue.length} remaining');
    } catch (e) {
      _logger.e('❌ Error processing offline queue: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Start periodic retry timer
  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (timer) {
      if (_queue.isNotEmpty) {
        _logger.i('⏰ Retry timer triggered, attempting to process queue...');
        _processQueue();
      }
    });
    _logger.i('✅ Retry timer started (every ${_retryInterval.inMinutes} minutes)');
  }

  /// Stop retry timer
  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _logger.i('🛑 Retry timer stopped');
  }

  /// Load queue from local storage
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList(_queueKey) ?? [];
      
      _queue = queueJson
          .map((json) => BeaconEvent.fromJson(jsonDecode(json)))
          .toList();
      
      _logger.i('📂 Loaded ${_queue.length} events from storage');
    } catch (e) {
      _logger.e('❌ Error loading offline queue: $e');
      _queue = [];
    }
  }

  /// Save queue to local storage
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = _queue
          .map((event) => jsonEncode(event.toJson()))
          .toList();
      
      await prefs.setStringList(_queueKey, queueJson);
      _logger.d('💾 Saved ${_queue.length} events to storage');
    } catch (e) {
      _logger.e('❌ Error saving offline queue: $e');
    }
  }

  /// Clear all queued events
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
    _logger.i('🗑️ Offline queue cleared');
  }

  /// Manual trigger to process queue
  Future<void> processNow() async {
    _logger.i('🔄 Manual queue processing triggered');
    await _processQueue();
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'queue_size': _queue.length,
      'is_processing': _isProcessing,
      'oldest_event': _queue.isEmpty 
          ? null 
          : _queue.first.timestamp.toIso8601String(),
      'newest_event': _queue.isEmpty 
          ? null 
          : _queue.last.timestamp.toIso8601String(),
    };
  }

  /// Dispose resources
  void dispose() {
    _retryTimer?.cancel();
    _logger.i('👋 Offline queue service disposed');
  }
}

