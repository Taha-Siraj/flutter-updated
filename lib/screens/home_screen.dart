import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_provider.dart';
import '../services/local_storage.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../widgets/status_indicator.dart';
import 'attendance_log_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  String _studentName = 'Student';

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _initializeProvider();
  }

  Future<void> _loadStudentInfo() async {
    await _localStorage.init();
    setState(() {
      _studentName = _localStorage.getStudentName();
    });
  }

  Future<void> _initializeProvider() async {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    // Set context for BLE dialogs
    if (mounted) {
      provider.setContext(context);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case AppConstants.bleConnected:
        return AppTheme.accentGreen;
      case AppConstants.bleScanning:
        return AppTheme.accentOrange;
      case AppConstants.bleDisconnected:
        return AppTheme.accentRed;
      default:
        return AppTheme.textGray;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case AppConstants.bleConnected:
        return Icons.bluetooth_connected;
      case AppConstants.bleScanning:
        return Icons.bluetooth_searching;
      case AppConstants.bleDisconnected:
        return Icons.bluetooth_disabled;
      default:
        return Icons.bluetooth;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy - HH:mm:ss').format(dateTime);
  }

  Widget _buildSignalStrengthBar(int rssi) {
    // Calculate signal strength percentage (0-100)
    // RSSI typically ranges from -30 (excellent) to -90 (poor)
    final percentage = ((rssi + 90) / 60 * 100).clamp(0, 100);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signal Strength',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textGray,
              ),
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            // Background bar
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Animated foreground bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              height: 8,
              width: MediaQuery.of(context).size.width * 0.6 * (percentage / 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: percentage > 60
                      ? [AppTheme.accentGreen, const Color(0xFF34D399)]
                      : percentage > 30
                          ? [AppTheme.accentOrange, const Color(0xFFFBBF24)]
                          : [AppTheme.accentRed, const Color(0xFFF87171)],
                ),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: (percentage > 60
                            ? AppTheme.accentGreen
                            : percentage > 30
                                ? AppTheme.accentOrange
                                : AppTheme.accentRed)
                        .withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$rssi dBm (${percentage.toInt()}%)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Smart Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AttendanceLogScreen(),
                ),
              );
            },
            tooltip: 'Attendance Log',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0B0C10),
                    const Color(0xFF1F2937),
                    const Color(0xFF0B0C10),
                  ]
                : [
                    const Color(0xFFF8F9FB),
                    const Color(0xFFE8F4F8),
                    const Color(0xFFF8F9FB),
                  ],
          ),
        ),
        child: SafeArea(
          child: Consumer<AttendanceProvider>(
            builder: (context, provider, child) {
              return RefreshIndicator(
                onRefresh: () async {
                  await provider.refresh();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Welcome Card (Glassmorphic)
                      GlassContainer(
                        borderRadius: BorderRadius.circular(25),
                        blur: 20,
                        opacity: isDark ? 0.1 : 0.3,
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.3),
                          width: 1.5,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryBlue.withOpacity(0.4),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _studentName.isNotEmpty
                                        ? _studentName[0].toUpperCase()
                                        : 'S',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome,',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    Text(
                                      _studentName,
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: -0.2, end: 0, duration: 600.ms),
                      
                      const SizedBox(height: 20),

                      // BLE Connection Status Card (Premium Glassmorphic)
                      GlassContainer(
                        borderRadius: BorderRadius.circular(25),
                        blur: 20,
                        opacity: isDark ? 0.1 : 0.3,
                        border: Border.all(
                          color: _getStatusColor(provider.bleStatus).withOpacity(0.4),
                          width: 2,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _getStatusColor(provider.bleStatus),
                                          _getStatusColor(provider.bleStatus).withOpacity(0.6),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _getStatusColor(provider.bleStatus)
                                              .withOpacity(0.4),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _getStatusIcon(provider.bleStatus),
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  )
                                      .animate(onPlay: (controller) => controller.repeat())
                                      .shimmer(duration: 2000.ms, color: Colors.white.withOpacity(0.3)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'BLE Connection',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            StatusIndicator(
                                              isActive: provider.bleStatus == AppConstants.bleConnected,
                                              size: 10,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              provider.bleStatus,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    color: _getStatusColor(provider.bleStatus),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 16),

                              // Beacon Information
                              _buildInfoRow(
                                context,
                                'Beacon ID',
                                provider.beaconId,
                                Icons.location_on_outlined,
                              ),
                              const SizedBox(height: 16),
                              
                              // Signal Strength with Animated Bar
                              if (provider.rssi != 0) _buildSignalStrengthBar(provider.rssi),
                              
                              const SizedBox(height: 16),
                              _buildInfoRow(
                                context,
                                'Last Updated',
                                _formatDateTime(provider.lastUpdated),
                                Icons.access_time,
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 200.ms)
                          .slideY(begin: -0.1, end: 0, duration: 600.ms),
                      
                      const SizedBox(height: 16),

                      // Background Service Status Card
                      FutureBuilder<bool>(
                        future: provider.isBackgroundServiceRunning(),
                        builder: (context, snapshot) {
                          final isRunning = snapshot.data ?? false;
                          return GlassContainer(
                            borderRadius: BorderRadius.circular(20),
                            blur: 15,
                            opacity: isDark ? 0.1 : 0.25,
                            border: Border.all(
                              color: (isRunning ? AppTheme.accentGreen : AppTheme.accentOrange)
                                  .withOpacity(0.5),
                              width: 1.5,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: (isRunning ? AppTheme.accentGreen : AppTheme.accentOrange)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isRunning ? Icons.check_circle : Icons.info,
                                      color: isRunning ? AppTheme.accentGreen : AppTheme.accentOrange,
                                      size: 28,
                                    ),
                                  )
                                      .animate(onPlay: (controller) => controller.repeat())
                                      .shake(duration: 2000.ms, hz: 0.5),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isRunning 
                                              ? 'Background Service Active'
                                              : 'Background Service Inactive',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isRunning
                                              ? 'Scanning continues when app is minimized'
                                              : 'Start scanning to enable background service',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 300.ms)
                          .slideY(begin: -0.1, end: 0, duration: 600.ms),
                      
                      const SizedBox(height: 20),

                      // Control Buttons with Gradient
                      if (!provider.isScanning)
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF34D399)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentGreen.withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await provider.startScanning();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Started BLE scanning'),
                                    backgroundColor: AppTheme.accentGreen,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow, color: Colors.white),
                            label: const Text(
                              'Start Scanning',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 600.ms, delay: 400.ms)
                            .scale(delay: 400.ms, duration: 400.ms)
                      else
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentRed.withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await provider.stopScanning();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Stopped BLE scanning'),
                                    backgroundColor: AppTheme.accentRed,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.stop, color: Colors.white),
                            label: const Text(
                              'Stop Scanning',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 600.ms, delay: 400.ms)
                            .scale(delay: 400.ms, duration: 400.ms),
                      
                      const SizedBox(height: 20),

                      // Recent Activity Card
                      GlassContainer(
                        borderRadius: BorderRadius.circular(25),
                        blur: 20,
                        opacity: isDark ? 0.1 : 0.3,
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.3),
                          width: 1.5,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Recent Activity',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const AttendanceLogScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text('View All'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      context,
                                      'Total Records',
                                      provider.attendanceRecords.length.toString(),
                                      Icons.event_note,
                                      AppTheme.primaryBlue,
                                      isDark,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      context,
                                      'Unsynced',
                                      provider.unsyncedRecords.length.toString(),
                                      Icons.sync_problem,
                                      AppTheme.accentOrange,
                                      isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 500.ms)
                          .slideY(begin: -0.1, end: 0, duration: 600.ms),
                      
                      const SizedBox(height: 20),

                      // Info Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryBlue.withOpacity(0.1),
                              AppTheme.secondaryBlue.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.primaryBlue.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppTheme.primaryBlue,
                              size: 24,
                            )
                                .animate(onPlay: (controller) => controller.repeat())
                                .shake(duration: 3000.ms, hz: 0.3),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'The app continuously scans for BLE beacons and automatically marks your attendance based on proximity.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 600.ms),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkTextSecondary
              : AppTheme.textGray,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(isDark ? 0.2 : 0.15),
            color.withOpacity(isDark ? 0.1 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32)
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(duration: 1500.ms, begin: const Offset(1.0, 1.0), end: const Offset(1.1, 1.1)),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(delay: 100.ms, duration: 400.ms);
  }
}
