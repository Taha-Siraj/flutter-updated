import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import '../utils/constants.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  final Logger _logger = Logger();
  BuildContext? _context;
  
  // BLE state
  final StreamController<String> _statusController = StreamController<String>.broadcast();
  final StreamController<String> _beaconIdController = StreamController<String>.broadcast();
  final StreamController<int> _rssiController = StreamController<int>.broadcast();
  
  Stream<String> get statusStream => _statusController.stream;
  Stream<String> get beaconIdStream => _beaconIdController.stream;
  Stream<int> get rssiStream => _rssiController.stream;
  
  String _currentStatus = AppConstants.bleNotFound;
  String _currentBeaconId = 'N/A';
  int _currentRssi = 0;
  
  bool _isScanning = false;
  Timer? _scanTimer;
  Timer? _simulationTimer;
  
  // Simulation mode (for testing without real BLE hardware)
  bool _simulationMode = false; // ✅ Production mode - real BLE scanning
  final Random _random = Random();
  final List<String> _mockBeacons = [
    'CLASSROOM_A',
    'CLASSROOM_B',
    'CLASSROOM_C',
    'LAB_101',
    'LIBRARY_MAIN',
  ];

  // Getters
  String get currentStatus => _currentStatus;
  String get currentBeaconId => _currentBeaconId;
  int get currentRssi => _currentRssi;
  bool get isScanning => _isScanning;

  // Initialize BLE
  Future<void> initialize() async {
    try {
      // Check if BLE is supported
      if (await FlutterBluePlus.isSupported == false) {
        _logger.w('BLE not supported, using simulation mode');
        _simulationMode = true;
        return;
      }

      // Check BLE adapter state
      FlutterBluePlus.adapterState.listen((state) {
        _logger.i('BLE Adapter state: $state');
        if (state == BluetoothAdapterState.on) {
          _simulationMode = false;
        } else {
          _logger.w('BLE adapter not on, using simulation mode');
          _simulationMode = true;
        }
      });
    } catch (e) {
      _logger.e('BLE initialization error: $e');
      _simulationMode = true;
    }
  }

  // Set context for dialogs
  void setContext(BuildContext context) {
    _context = context;
  }

  // 🎯 Check Bluetooth state before scanning
  Future<bool> _checkBluetoothEnabled() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _logger.w('⚠️ Bluetooth not supported on this device');
        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            const SnackBar(
              content: Text('❌ Bluetooth not supported on this device'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState == BluetoothAdapterState.on) {
        _logger.i('✅ Bluetooth is ON');
        return true;
      }

      // Bluetooth is OFF - show dialog
      _logger.w('⚠️ Bluetooth is OFF');
      if (_context != null && _context!.mounted) {
        final shouldEnable = await showDialog<bool>(
          context: _context!,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Expanded(child: Text('Bluetooth is Off')),
              ],
            ),
            content: const Text(
              'Bluetooth is currently disabled. Please enable Bluetooth to start scanning for attendance beacons.',
              style: TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.bluetooth, color: Colors.white),
                label: const Text('Enable Bluetooth'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0061FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              if (_context!.mounted) {
                ScaffoldMessenger.of(_context!).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Bluetooth enabled successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              return true;
            }
          } catch (e) {
            _logger.e('Error enabling Bluetooth: $e');
            if (_context!.mounted) {
              ScaffoldMessenger.of(_context!).showSnackBar(
                const SnackBar(
                  content: Text('❌ Failed to enable Bluetooth. Please enable manually.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }

      return false;
    } catch (e) {
      _logger.e('Error checking Bluetooth: $e');
      return false;
    }
  }

  // Start scanning for beacons
  Future<void> startScanning() async {
    if (_isScanning) {
      _logger.w('Already scanning');
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Scanning is already active'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // 🎯 Check Bluetooth before starting scan
    final bluetoothEnabled = await _checkBluetoothEnabled();
    if (!bluetoothEnabled) {
      _logger.w('Cannot start scanning - Bluetooth not enabled');
      return;
    }

    _isScanning = true;
    _updateStatus(AppConstants.bleScanning);
    _logger.i('Started BLE scanning');

    if (_simulationMode) {
      _startSimulation();
    } else {
      _startRealScanning();
    }
  }

  // Stop scanning
  Future<void> stopScanning() async {
    if (!_isScanning) return;

    _isScanning = false;
    _scanTimer?.cancel();
    _simulationTimer?.cancel();
    
    if (!_simulationMode) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        _logger.e('Error stopping scan: $e');
      }
    }

    _updateStatus(AppConstants.bleNotFound);
    _updateBeaconId('N/A');
    _updateRssi(0);
    _logger.i('Stopped BLE scanning');
  }

  // Real BLE scanning (when hardware available)
  void _startRealScanning() {
    _logger.i('🔄 Starting CONTINUOUS real BLE scanning (no 10s resets)...');
    
    // Listen to scan results continuously
    FlutterBluePlus.scanResults.listen((results) {
      if (!_isScanning) return; // Ignore if stopped
      
      if (results.isNotEmpty) {
        // Find the closest beacon (strongest signal)
        ScanResult? closestBeacon;
        for (var result in results) {
          if (closestBeacon == null || result.rssi > closestBeacon.rssi) {
            closestBeacon = result;
          }
        }

        if (closestBeacon != null) {
          _handleBeaconDetection(
            closestBeacon.device.platformName.isNotEmpty
                ? closestBeacon.device.platformName
                : closestBeacon.device.remoteId.toString(),
            closestBeacon.rssi,
          );
        }
      } else {
        // No beacons found in this cycle
        if (_currentStatus != AppConstants.bleScanning) {
          _updateStatus(AppConstants.bleScanning);
        }
      }
    });

    // 🎯 TRUE CONTINUOUS SCANNING: Start once and keep alive
    _startContinuousBleScanning();

    // Periodic health check (every 30 seconds) to ensure scanning continues
    _scanTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isScanning) {
        timer.cancel();
        return;
      }
      
      try {
        // Check if Bluetooth is still on
        final adapterState = await FlutterBluePlus.adapterState.first;
        if (adapterState != BluetoothAdapterState.on) {
          _logger.w('⚠️ Bluetooth turned off during health check');
          _updateStatus(AppConstants.bleNotFound);
          _updateBeaconId('N/A');
          _updateRssi(0);
          return;
        }

        // Check if scan is actually running
        final isScanningNow = FlutterBluePlus.isScanningNow;
        if (!isScanningNow) {
          _logger.w('⚠️ Scan stopped unexpectedly, restarting...');
          await _startContinuousBleScanning();
        } else {
          _logger.i('✅ Health check: BLE scanning active');
        }
        
      } catch (e) {
        _logger.e('❌ Health check error: $e');
        // Try to restart scan
        try {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 500));
          await _startContinuousBleScanning();
        } catch (restartError) {
          _logger.e('Failed to restart scan: $restartError');
        }
      }
    });

    // Monitor adapter state for reconnection
    FlutterBluePlus.adapterState.listen((state) {
      _logger.i('📡 BLE Adapter state changed: $state');
      if (state == BluetoothAdapterState.on && _isScanning) {
        _logger.i('✅ Bluetooth re-enabled, resuming continuous scan');
        _startContinuousBleScanning();
      } else if (state != BluetoothAdapterState.on) {
        _logger.w('⚠️ Bluetooth disabled');
        _updateStatus(AppConstants.bleNotFound);
        _updateBeaconId('N/A');
        _updateRssi(0);
      }
    });
  }
  
  // Start continuous BLE scanning (no timeout)
  Future<void> _startContinuousBleScanning() async {
    try {
      _logger.i('🚀 Starting BLE scan with NO TIMEOUT (truly continuous)');
      
      // Stop any existing scan first
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {
        // Ignore
      }
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Start scan WITHOUT timeout = continuous scanning
      await FlutterBluePlus.startScan(
        // NO timeout parameter = scan runs indefinitely until manually stopped
        androidUsesFineLocation: true,
      );
      
      _logger.i('✅ Continuous BLE scan started successfully');
    } catch (e) {
      _logger.e('❌ Failed to start continuous scan: $e');
    }
  }

  // Simulation mode for testing
  void _startSimulation() {
    int consecutiveScans = 0;
    
    _simulationTimer = Timer.periodic(AppConstants.scanInterval, (timer) {
      consecutiveScans++;
      
      // 80% chance of finding a beacon
      if (_random.nextDouble() < 0.8) {
        // Pick a random beacon
        final beaconId = _mockBeacons[_random.nextInt(_mockBeacons.length)];
        
        // Generate realistic RSSI (-40 to -90 dBm)
        // Stronger signal for first few scans, then vary
        int rssi;
        if (consecutiveScans < 3) {
          rssi = -50 + _random.nextInt(15); // -50 to -65 (strong signal)
        } else {
          rssi = -60 + _random.nextInt(30); // -60 to -90 (varying signal)
        }
        
        _handleBeaconDetection(beaconId, rssi);
      } else {
        // 20% chance beacon not found
        _updateStatus(AppConstants.bleNotFound);
        _updateBeaconId('N/A');
        _updateRssi(0);
        consecutiveScans = 0;
      }
    });
  }

  // Handle beacon detection
  void _handleBeaconDetection(String beaconId, int rssi) {
    _updateBeaconId(beaconId);
    _updateRssi(rssi);

    // Check signal strength
    if (rssi >= AppConstants.rssiThreshold) {
      _updateStatus(AppConstants.bleConnected);
    } else {
      _updateStatus(AppConstants.bleDisconnected);
    }
  }

  // Update status
  void _updateStatus(String status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  // Update beacon ID
  void _updateBeaconId(String beaconId) {
    _currentBeaconId = beaconId;
    _beaconIdController.add(beaconId);
  }

  // Update RSSI
  void _updateRssi(int rssi) {
    _currentRssi = rssi;
    _rssiController.add(rssi);
  }

  // Check if in range (for attendance marking)
  bool isInRange() {
    return _currentStatus == AppConstants.bleConnected &&
           _currentRssi >= AppConstants.rssiThreshold;
  }

  // Dispose streams
  void dispose() {
    _statusController.close();
    _beaconIdController.close();
    _rssiController.close();
    _scanTimer?.cancel();
    _simulationTimer?.cancel();
  }
}

