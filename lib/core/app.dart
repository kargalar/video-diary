import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_routes.dart';
import '../features/diary/viewmodel/diary_view_model.dart';
import '../features/settings/viewmodel/settings_view_model.dart';
import 'di/service_locator.dart';

class VideoDiaryApp extends StatelessWidget {
  const VideoDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsViewModel(sl.settingsRepository, sl.notificationService)..load()),
        ChangeNotifierProvider(create: (_) => DiaryViewModel(sl.diaryRepository, sl.settingsRepository, sl.dayDataRepository, sl.moodRepository, sl.notificationService)),
        ChangeNotifierProvider.value(value: sl.recordingDependencies.recordViewModel),
      ],
      child: Consumer<SettingsViewModel>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Video Diary',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C2C2C), brightness: Brightness.light, primary: const Color(0xFF2C2C2C), secondary: const Color(0xFF5C5C5C), surface: Colors.white, surfaceContainerHighest: const Color(0xFFF5F5F5)),
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true, backgroundColor: Colors.white, foregroundColor: Color(0xFF2C2C2C)),
            dividerColor: const Color(0xFFE0E0E0),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF2C2C2C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: const Color(0xFF5C5C5C))),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C2C2C), brightness: Brightness.dark, primary: const Color(0xFFE0E0E0), secondary: const Color(0xFFB0B0B0), surface: const Color(0xFF1A1A1A), surfaceContainerHighest: const Color(0xFF2C2C2C)),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF1A1A1A),
            appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true, backgroundColor: Color(0xFF1A1A1A), foregroundColor: Color(0xFFE0E0E0)),
            dividerColor: const Color(0xFF3C3C3C),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF3C3C3C), width: 1),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: const Color(0xFFE0E0E0))),
          ),
          themeMode: ThemeMode.dark,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}
