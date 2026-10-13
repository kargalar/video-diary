import 'package:flutter/material.dart';
import '../../features/diary/view/diary_page.dart';
import '../../features/diary/view/player_page.dart';
import '../../features/diary/view/recording_page.dart';
import '../../features/settings/view/settings_page.dart';
import '../../features/settings/view/debug_page.dart';

/// Application route definitions.
class AppRoutes {
  AppRoutes._();

  // Route names.
  static const String home = '/';
  static const String player = PlayerPage.route;
  static const String record = RecordingPage.route;
  static const String settings = SettingsPage.route;
  static const String debug = DebugPage.route;

  // Route map.
  static Map<String, WidgetBuilder> get routes => {home: (context) => const DiaryPage()};

  // --- Custom Route Builders ---

  /// Right-to-left page transition.
  static Route<T> _slideRightToLeftRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  /// Bottom-to-top page transition.
  static Route<T> _slideBottomToTopRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  /// Scale-up transition from the center.
  static Route<T> _scaleFromCenterRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeInOut;
        var tween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
        return ScaleTransition(scale: animation.drive(tween), alignment: Alignment.center, child: child);
      },
    );
  }

  // --- onGenerateRoute ---
  static Route<dynamic>? onGenerateRoute(RouteSettings settingsRoute) {
    if (settingsRoute.name == player && settingsRoute.arguments is PlayerPageArgs) {
      final args = settingsRoute.arguments as PlayerPageArgs;
      return _slideBottomToTopRoute(PlayerPage(args: args));
    } else if (settingsRoute.name == record) {
      return _scaleFromCenterRoute(const RecordingPage());
    } else if (settingsRoute.name == settings) {
      return _slideRightToLeftRoute(const SettingsPage());
    } else if (settingsRoute.name == debug) {
      return _slideRightToLeftRoute(const DebugPage());
    }
    return null;
  }

  // --- Navigation Methods ---

  // Navigate home and clear the navigation history.
  static void goToHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, home, (_) => false);
  }

  // Navigate to settings with a right-to-left transition.
  static void goToSettings(BuildContext context) {
    Navigator.push(context, _slideRightToLeftRoute(const SettingsPage()));
  }

  // Navigate to recording with a center-scale transition.
  static Future<dynamic> goToRecord(BuildContext context) {
    return Navigator.push(context, _scaleFromCenterRoute(const RecordingPage()));
  }

  // Navigate to the player with a bottom-to-top transition.
  static void goToPlayer(BuildContext context, PlayerPageArgs args) {
    Navigator.push(context, _slideBottomToTopRoute(PlayerPage(args: args)));
  }

  // Navigate to debug with a right-to-left transition.
  static void goToDebug(BuildContext context) {
    Navigator.push(context, _slideRightToLeftRoute(const DebugPage()));
  }

  // Navigate back.
  static void goBack(BuildContext context) {
    Navigator.pop(context);
  }
}
