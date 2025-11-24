import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class PermissionHandlerService {
  static final PermissionHandlerService _instance = PermissionHandlerService._internal();
  factory PermissionHandlerService() => _instance;
  PermissionHandlerService._internal();

  final Logger _logger = Logger();

  // 🎯 UI-FRIENDLY: Request all permissions with BuildContext for dialogs
  static Future<void> requestAllPermissions(BuildContext context) async {
    final service = PermissionHandlerService();
    
    if (!Platform.isAndroid) {
      service._logger.i('iOS permissions handled by Info.plist');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Permissions handled by system'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    service._logger.i('🔐 Requesting Android permissions with UI...');

    try {
      // Check Bluetooth first
      bool bluetooth = await service._checkBluetooth(context);
      
      // Request Location
      bool location = await service._requestPermission(
        Permission.location,
        context,
        'Location',
      );
      
      // Request Bluetooth Scan & Connect (Android 12+)
      bool bluetoothScan = await service._requestPermission(
        Permission.bluetoothScan,
        context,
        'Bluetooth Scan',
      );
      
      bool bluetoothConnect = await service._requestPermission(
        Permission.bluetoothConnect,
        context,
        'Bluetooth Connect',
      );
      
      // Request Notifications (Android 13+)
      await service._requestPermission(
        Permission.notification,
        context,
        'Notifications',
      );

      if (context.mounted) {
        if (bluetooth && location && bluetoothScan && bluetoothConnect) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ All permissions granted successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ Some permissions denied. Please enable manually.'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Open Settings',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      service._logger.e('❌ Permission request error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error requesting permissions'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Request a single permission with fallback to settings
  Future<bool> _requestPermission(
    Permission permission,
    BuildContext context,
    String label,
  ) async {
    try {
      var status = await permission.status;
      
      if (status.isGranted) {
        _logger.i('✅ $label permission already granted');
        return true;
      }
      
      if (status.isDenied) {
        _logger.i('🔐 Requesting $label permission...');
        var result = await permission.request();
        
        if (result.isGranted) {
          _logger.i('✅ $label permission granted');
          return true;
        } else if (result.isPermanentlyDenied) {
          _logger.w('⚠️ $label permission permanently denied');
          if (context.mounted) {
            _showSettingsDialog(context, label);
          }
          return false;
        }
      }
      
      if (status.isPermanentlyDenied) {
        _logger.w('⚠️ $label permission permanently denied');
        if (context.mounted) {
          _showSettingsDialog(context, label);
        }
        return false;
      }
      
      return false;
    } catch (e) {
      _logger.e('Error requesting $label permission: $e');
      return false;
    }
  }

  // Check and prompt for Bluetooth enable
  Future<bool> _checkBluetooth(BuildContext context) async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _logger.w('⚠️ Bluetooth not supported on this device');
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState == BluetoothAdapterState.on) {
        _logger.i('✅ Bluetooth is ON');
        return true;
      }

      // Bluetooth is OFF - show dialog
      _logger.w('⚠️ Bluetooth is OFF');
      if (context.mounted) {
        final shouldEnable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.orange),
                SizedBox(width: 8),
                Text('Bluetooth Required'),
              ],
            ),
            content: const Text(
              'Bluetooth is currently disabled. Please enable Bluetooth to start scanning for attendance beacons.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.bluetooth),
                label: const Text('Enable Bluetooth'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0061FF),
                ),
              ),
            ],
          ),
        );

        if (shouldEnable == true) {
          try {
            if (Platform.isAndroid) {
              await FlutterBluePlus.turnOn();
              _logger.i('✅ Bluetooth enabled');
              return true;
            }
          } catch (e) {
            _logger.e('Error enabling Bluetooth: $e');
          }
        }
      }

      return false;
    } catch (e) {
      _logger.e('Error checking Bluetooth: $e');
      return false;
    }
  }

  // Show settings dialog
  void _showSettingsDialog(BuildContext context, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$type Permission Required'),
        content: Text(
          'This app needs $type permission to function properly. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0061FF),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Legacy method for backwards compatibility (without UI)
  Future<bool> requestAllPermissionsLegacy() async {
    if (!Platform.isAndroid) {
      _logger.i('iOS permissions handled by Info.plist');
      return true;
    }

    _logger.i('🔐 Requesting Android permissions...');
    
    bool allGranted = true;

    try {
      // 1. Bluetooth permissions (Android 12+)
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      
      if (!bluetoothScan.isGranted || !bluetoothConnect.isGranted) {
        _logger.w('⚠️ Bluetooth permissions denied');
        allGranted = false;
      } else {
        _logger.i('✅ Bluetooth permissions granted');
      }

      // 2. Location permissions (required for BLE scanning)
      final locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        _logger.w('⚠️ Location permission denied');
        allGranted = false;
      } else {
        _logger.i('✅ Location permission granted');
      }

      // 3. Notification permission (Android 13+)
      final notificationStatus = await Permission.notification.request();
      if (!notificationStatus.isGranted) {
        _logger.w('⚠️ Notification permission denied (optional)');
        // Not critical, don't fail
      } else {
        _logger.i('✅ Notification permission granted');
      }

      _logger.i('Permission request complete. All granted: $allGranted');
      return allGranted;
    } catch (e) {
      _logger.e('❌ Permission request error: $e');
      return false;
    }
  }

  // Check permission status
  Future<Map<String, bool>> checkPermissionStatus() async {
    if (!Platform.isAndroid) {
      return {'all_granted': true};
    }

    Map<String, bool> status = {};

    try {
      status['bluetooth_scan'] = await Permission.bluetoothScan.isGranted;
      status['bluetooth_connect'] = await Permission.bluetoothConnect.isGranted;
      status['location'] = await Permission.location.isGranted;
      status['notification'] = await Permission.notification.isGranted;

      status['all_granted'] = status['bluetooth_scan']! && 
                              status['bluetooth_connect']! && 
                              status['location']!;
    } catch (e) {
      _logger.e('Error checking permissions: $e');
      status['all_granted'] = false;
    }
    
    return status;
  }

  // Request battery optimization exemption
  Future<void> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    try {
      _logger.i('🔋 Requesting battery optimization exemption...');
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (status.isGranted) {
        _logger.i('✅ Battery optimization disabled');
      } else {
        _logger.w('⚠️ Battery optimization not disabled');
      }
    } catch (e) {
      _logger.e('❌ Battery optimization request error: $e');
    }
  }

  // Check if battery optimization is disabled
  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      return false;
    }
  }

}

