import 'package:flutter/material.dart';
import 'screens/home.dart';
import 'services/sync_service.dart';
import 'services/wifi_settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WiFiSettingsService.instance.initialize();
  SyncService.instance.start();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Potato Scan',
      home: Home(),
    );
  }
}
