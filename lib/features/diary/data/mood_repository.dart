import 'package:hive_flutter/hive_flutter.dart';

import '../model/mood.dart';

class MoodRepository {
  static const _boxName = 'mood_catalog';
  static const _catalogKey = 'moods';
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
    _inited = true;
  }

  Future<List<Mood>> load() async {
    await init();
    final box = Hive.box(_boxName);
    final raw = box.get(_catalogKey);
    if (raw is! List || raw.isEmpty) {
      final defaults = List<Mood>.from(Mood.defaults);
      await save(defaults);
      return defaults;
    }

    final moods = raw.map(Mood.fromDynamic).whereType<Mood>().fold<List<Mood>>([], (list, mood) {
      if (list.any((existing) => existing.id == mood.id)) return list;
      return [...list, mood];
    });

    if (moods.isEmpty) {
      final defaults = List<Mood>.from(Mood.defaults);
      await save(defaults);
      return defaults;
    }

    return moods;
  }

  Future<void> save(List<Mood> moods) async {
    await init();
    final box = Hive.box(_boxName);
    await box.put(_catalogKey, moods.map((mood) => mood.toJson()).toList());
  }
}
