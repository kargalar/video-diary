import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';

import '../model/settings.dart';

class SettingsRepository {
  static const _boxName = 'settings';
  bool _inited = false;

  final _settingsStreamController = StreamController<SettingsModel>.broadcast();
  Stream<SettingsModel> get onSettingsChanged => _settingsStreamController.stream;

  Future<void> init() async {
    if (_inited) return;
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
    _inited = true;
  }

  Future<SettingsModel> load() async {
    await init();
    final box = Hive.box(_boxName);
    final raw = box.get('settings');
    if (raw == null) return SettingsModel.def;
    return SettingsModel.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> save(SettingsModel settings) async {
    await init();
    final box = Hive.box(_boxName);
    await box.put('settings', settings.toJson());
    _settingsStreamController.add(settings);
  }
}
