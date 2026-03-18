import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/db_service.dart';
import 'providers/db_provider.dart';
import 'ui/app_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbService = DbService();
  await dbService.init();

  runApp(
    ProviderScope(
      overrides: [
        dbServiceProvider.overrideWithValue(dbService),
      ],
      child: const KhataApp(),
    ),
  );
}

class KhataApp extends StatelessWidget {
  const KhataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khata Book',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005CEE), // KhataBook brand blue
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AppLockScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
