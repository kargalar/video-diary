import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app.dart';
import 'core/di/service_locator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure services are fully initialized before the app starts
  await sl.setup();
  // Lock the entire app to portrait by default; specific pages can override temporarily
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(const VideoDiaryApp());
}
