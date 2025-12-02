import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/local_storage.dart';
import '../providers/attendance_provider.dart';
import '../providers/theme_provider.dart';
import '../services/permission_handler_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  
  bool _backgroundScanningEnabled = true;
  bool _notificationsEnabled = true;
  String _studentName = '';
  String _studentId = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _localStorage.init();
    setState(() {
      _backgroundScanningEnabled = _localStorage.isBackgroundScanningEnabled();
      _notificationsEnabled = _localStorage.isNotificationsEnabled();
      _studentName = _localStorage.getStudentName();
      _studentId = _localStorage.getStudentId();
      _email = _localStorage.getEmail();
    });
  }

  Future<void> _toggleBackgroundScanning(bool value) async {
    await _localStorage.setBackgroundScanningEnabled(value);
    setState(() {
      _backgroundScanningEnabled = value;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Background scanning enabled'
              : 'Background scanning disabled',
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    await _localStorage.setNotificationsEnabled(value);
    setState(() {
      _notificationsEnabled = value;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? 'Notifications enabled' : 'Notifications disabled',
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to logout? Unsynced data will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Stop scanning if active
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      if (provider.isScanning) {
        await provider.stopScanning();
      }

      // Clear local storage
      await _localStorage.logout();

      if (!mounted) return;

      // Navigate to login
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppTheme.primaryBlue,
                      child: Text(
                        _studentName.isNotEmpty
                            ? _studentName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _studentName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                      ),
                    ),
                    if (_studentId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ID: $_studentId',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Settings Section
            Text(
              'Preferences',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),

            // Background Scanning Toggle
            Card(
              child: SwitchListTile(
                value: _backgroundScanningEnabled,
                onChanged: _toggleBackgroundScanning,
                title: Text(
                  'Enable Background Scanning',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextPrimary : null,
                  ),
                ),
                subtitle: Text(
                  'Allow app to scan for beacons in the background',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                  ),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.settings_backup_restore,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                activeThumbColor: AppTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 12),

            // Notifications Toggle
            Card(
              child: SwitchListTile(
                value: _notificationsEnabled,
                onChanged: _toggleNotifications,
                title: Text(
                  'Enable Notifications',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextPrimary : null,
                  ),
                ),
                subtitle: Text(
                  'Get notified about attendance updates',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                  ),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                activeThumbColor: AppTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 12),

            // Dark Theme Toggle
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return Card(
                  child: SwitchListTile(
                    value: themeProvider.isDarkMode,
                    onChanged: (value) async {
                      await themeProvider.toggleTheme();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            themeProvider.isDarkMode 
                                ? 'Dark theme enabled'
                                : 'Light theme enabled',
                          ),
                          backgroundColor: AppTheme.primaryBlue,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    title: Text(
                      'Dark Theme',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppTheme.darkTextPrimary : null,
                      ),
                    ),
                    subtitle: Text(
                      'Switch between light and dark mode',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                      ),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    activeThumbColor: AppTheme.accentGreen,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Request Permissions Button
            Card(
              elevation: 4,
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lock_open_rounded,
                    color: Colors.amber,
                  ),
                ),
                title: Text(
                  'Request Permissions',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextPrimary : null,
                  ),
                ),
                subtitle: Text(
                  'Grant Bluetooth, Location & Notification access',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => PermissionHandlerService.requestAllPermissions(context),
              ),
            ),
            const SizedBox(height: 12),

            // Battery Optimization Button
            Card(
              elevation: 4,
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.battery_saver,
                    color: AppTheme.accentGreen,
                  ),
                ),
                title: Text(
                  'Disable Battery Optimization',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextPrimary : null,
                  ),
                ),
                subtitle: Text(
                  'Allow background scanning without restrictions',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await PermissionHandlerService().requestBatteryOptimization();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Battery optimization request sent'),
                      backgroundColor: AppTheme.accentGreen,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),

            // Logout Button
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentRed,
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Info Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.textGray.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppTheme.textGray.withValues(alpha: 0.5),
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your data is stored locally and synced automatically.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textGray,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.appVersion,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: AppTheme.textGray.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

