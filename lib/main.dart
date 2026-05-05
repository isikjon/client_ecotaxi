import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'styles/app_theme.dart';
import 'screens/auth/phone_auth_screen.dart';
import 'screens/main/simple_main_screen.dart';
import 'screens/location_permission_screen.dart';

late sdk.Context sdkContext;
bool isSdkInitialized = false;

void main() async {
  // Используем фиксированную версию ErrorWidget.builder до инициализации
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const Text('Ошибка инициализации'),
              Text(details.exception.toString()),
            ],
          ),
        ),
      ),
    );
  };

  // 1. Глобальный перехват ошибок Flutter (Rendering, UI)
  FlutterError.onError = (FlutterErrorDetails details) {
    print('⚠️ Flutter Error: ${details.exception}');
  };

  // 2. Перехват ошибок платформы и асинхронных вызовов
  PlatformDispatcher.instance.onError = (error, stack) {
    print('⚠️ Platform Error: $error');
    return true; 
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Кастомный экран ошибки для основного приложения
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                const Text(
                  'Произошла ошибка в приложении',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Мы уже работаем над исправлением. Попробуйте перезапустить приложение.',
                  textAlign: TextAlign.center,
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text(details.exception.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => exit(0),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      );
    };

    try {
      final iosKey = const sdk.KeyFromAsset('dgissdk_ios.key');
      final androidKey = const sdk.KeyFromAsset('dgissdk.key');

      final keySource = sdk.KeySource.fromAsset(Platform.isAndroid ? androidKey : iosKey);

      // Удаляем .timeout(), так как он вызывает ошибку компиляции
      sdkContext = await sdk.DGis.initialize(keySource: keySource);
      isSdkInitialized = true;
      print('✅ 2GIS SDK инициализирован успешно');
    } catch (e) {
      print('⚠️ Ошибка инициализации SDK: $e');
      try {
        sdkContext = await sdk.DGis.initialize();
        isSdkInitialized = true;
        print('✅ 2GIS SDK инициализирован без ключа');
      } catch (e2) {
        print('❌ Критическая ошибка SDK: $e2');
        // Создаем пустой контекст если совсем всё плохо, чтобы late переменная была инициализирована
        // но лучше сделать её nullable и проверять везде
      }
    }

    runApp(const TaxiApp());
  }, (error, stack) {
    print('❌ Глобальная ошибка: $error');
  });
}

class TaxiApp extends StatelessWidget {
  const TaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eco Такси',
      theme: AppTheme.lightTheme,
      home: const LocationPermissionScreen(
        nextScreen: AuthWrapper(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _savedPhoneNumber;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await LocationService().initialize();
    } catch (e) {
      print('Ошибка инициализации LocationService: $e');
    }
    
    await _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isLoggedIn = await AuthService.isLoggedIn();
      final clientData = await AuthService.getCurrentClient();
      
      setState(() {
        _isLoggedIn = isLoggedIn;
        _savedPhoneNumber = clientData?['phoneNumber'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // if (_isLoading) {
    //   return const Scaffold(
    //     body: Center(
    //       child: CircularProgressIndicator(),
    //     ),
    //   );
    // }

    if (_isLoggedIn) {
      return const SimpleMainScreen();
    } else {
      return const PhoneAuthScreen();
    }
  }
}

