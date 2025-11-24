import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/beacon_event.dart';
import '../models/beacon_mapping.dart';
import '../services/background_ble.dart';
import '../services/offline_queue.dart';
import '../services/attendance_api.dart';
import '../utils/theme.dart';

/// Production Attendance Dashboard
/// Shows real-time BLE status, beacon detection, and attendance events
class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({super.key});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> {
  final BackgroundBleService _bleService = BackgroundBleService();
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  final AttendanceApiService _apiService = AttendanceApiService();
  
  bool _isScanning = false;
  String? _currentBeacon;
  List<BeaconEvent> _recentEvents = [];
  List<BeaconMapping> _beaconMappings = [];
  int _offlineQueueSize = 0;
  
  StreamSubscription<BeaconEvent>? _eventSubscription;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _bleService.initialize();
    
    // Listen to attendance events
    _eventSubscription = _bleService.eventStream.listen((event) {
      setState(() {
        _recentEvents.insert(0, event);
        if (_recentEvents.length > 50) {
          _recentEvents.removeRange(50, _recentEvents.length);
        }
        _currentBeacon = event.beaconId;
      });
    });
    
    // Periodic status update
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateStatus();
    });
    
    // Initial status update
    _updateStatus();
  }

  Future<void> _updateStatus() async {
    final isRunning = await _bleService.isServiceRunning();
    final stats = _bleService.getStatistics();
    final queueStats = _offlineQueue.getStatistics();
    
    if (mounted) {
      setState(() {
        _isScanning = isRunning;
        _currentBeacon = stats['current_beacon'];
        _beaconMappings = _bleService.beaconMappings;
        _offlineQueueSize = queueStats['queue_size'] ?? 0;
      });
    }
  }

  Future<void> _toggleScanning() async {
    if (_isScanning) {
      // Stop scanning
      final success = await _bleService.stopScanning();
      if (success) {
        _showSnackBar('✅ BLE scanning stopped', Colors.orange);
        setState(() {
          _isScanning = false;
          _currentBeacon = null;
        });
      }
    } else {
      // Start scanning
      if (!_apiService.isAuthenticated) {
        _showSnackBar('❌ Not authenticated. Please login first.', Colors.red);
        return;
      }
      
      final success = await _bleService.startScanning(
        authToken: _apiService.authToken!,
        studentId: _apiService.studentId!,
        apiBaseUrl: _apiService.baseUrl,
      );
      
      if (success) {
        _showSnackBar('✅ BLE scanning started', Colors.green);
        setState(() {
          _isScanning = true;
        });
      } else {
        _showSnackBar('❌ Failed to start scanning', Colors.red);
      }
    }
  }

  Future<void> _syncOfflineQueue() async {
    if (_offlineQueueSize == 0) {
      _showSnackBar('ℹ️ No offline events to sync', Colors.blue);
      return;
    }
    
    _showSnackBar('🔄 Syncing offline events...', Colors.blue);
    await _offlineQueue.processNow();
    
    // Wait a bit and update
    await Future.delayed(const Duration(seconds: 2));
    _updateStatus();
    
    _showSnackBar('✅ Sync complete', Colors.green);
  }

  Future<void> _refreshBeaconMappings() async {
    _showSnackBar('🔄 Refreshing beacon mappings...', Colors.blue);
    await _bleService.fetchBeaconMappings();
    _updateStatus();
    _showSnackBar('✅ Beacon mappings refreshed', Colors.green);
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Attendance Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshBeaconMappings,
            tooltip: 'Refresh Beacon Mappings',
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _offlineQueueSize > 0,
              label: Text('$_offlineQueueSize'),
              child: const Icon(Icons.cloud_upload),
            ),
            onPressed: _syncOfflineQueue,
            tooltip: 'Sync Offline Queue',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _updateStatus();
          await _refreshBeaconMappings();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              _buildStatusCard(),
              
              const SizedBox(height: 20),
              
              // Current Beacon Card
              _buildCurrentBeaconCard(),
              
              const SizedBox(height: 20),
              
              // Statistics
              _buildStatisticsRow(),
              
              const SizedBox(height: 20),
              
              // Recent Events
              _buildRecentEvents(),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _isScanning
            ? const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0061FF)],
              )
            : LinearGradient(
                colors: [Colors.grey.shade400, Colors.grey.shade600],
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _isScanning
                ? const Color(0xFF0061FF).withOpacity(0.3)
                : Colors.grey.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isScanning ? 'BLE Scanning Active' : 'BLE Scanning Inactive',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isScanning
                      ? 'Background service is running'
                      : 'Tap button to start scanning',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _isScanning ? Icons.check_circle : Icons.cancel,
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentBeaconCard() {
    final mapping = _currentBeacon != null
        ? _bleService.getBeaconMapping(_currentBeacon!)
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _currentBeacon != null
              ? const Color(0xFF5CE1E6)
              : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _currentBeacon != null
                    ? Icons.location_on
                    : Icons.location_off,
                color: _currentBeacon != null
                    ? const Color(0xFF0061FF)
                    : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Current Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_currentBeacon != null && mapping != null) ...[
            _buildInfoRow('Classroom', mapping.classroomName),
            _buildInfoRow('Beacon ID', _currentBeacon!),
            if (mapping.sessionName != null)
              _buildInfoRow('Session', mapping.sessionName!),
            if (mapping.courseName != null)
              _buildInfoRow('Course', mapping.courseName!),
            if (mapping.isSessionActive)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Session Active',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.search, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      _isScanning
                          ? 'Searching for beacons...'
                          : 'No beacon detected',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Beacon Mappings',
            '${_beaconMappings.length}',
            Icons.map,
            const Color(0xFF0061FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Offline Queue',
            '$_offlineQueueSize',
            Icons.cloud_queue,
            _offlineQueueSize > 0 ? Colors.orange : Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Recent Events',
            '${_recentEvents.length}',
            Icons.event,
            const Color(0xFF5CE1E6),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Events',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        if (_recentEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'No events yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(
            _recentEvents.length > 10 ? 10 : _recentEvents.length,
            (index) => _buildEventCard(_recentEvents[index]),
          ),
      ],
    );
  }

  Widget _buildEventCard(BeaconEvent event) {
    final mapping = _bleService.getBeaconMapping(event.beaconId);
    final eventColor = _getEventColor(event.event);
    final eventIcon = _getEventIcon(event.event);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: eventColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: eventColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(eventIcon, color: eventColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.event.toUpperCase(),
                  style: TextStyle(
                    color: eventColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (mapping != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    mapping.classroomName,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(event.timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (event.synced)
            const Icon(Icons.cloud_done, color: Colors.green, size: 20)
          else
            const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
        ],
      ),
    );
  }

  Color _getEventColor(String event) {
    switch (event.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'left':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getEventIcon(String event) {
    switch (event.toLowerCase()) {
      case 'present':
        return Icons.check_circle;
      case 'left':
        return Icons.exit_to_app;
      case 'absent':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: _toggleScanning,
      backgroundColor: _isScanning ? Colors.orange : const Color(0xFF0061FF),
      icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
      label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
    );
  }
}

