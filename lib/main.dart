import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'providers/attendance_provider.dart';
import 'providers/theme_provider.dart';
import 'services/permission_handler_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ⭐ Initialize core services
  try {
    // 1. Notification service
    await NotificationService().initialize();
    
    // 2. Background service
    await BackgroundService().initialize();
    
    // 3. Request permissions (legacy method without UI on startup)
    await PermissionHandlerService().requestAllPermissionsLegacy();
    
  } catch (e) {
    debugPrint('❌ Service initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..initialize()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Smart Attendance',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

