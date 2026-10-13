import 'package:hive_flutter/hive_flutter.dart';

import '../model/diary_entry.dart';

class DiaryRepository {
  DiaryRepository({
    Future<void> Function()? hiveInitializer,
    String boxName = 'diary_entries',
  }) : _hiveInitializer = hiveInitializer,
       _boxName = boxName;

  final Future<void> Function()? _hiveInitializer;
  final String _boxName;
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    final initializer = _hiveInitializer;
    if (initializer == null) {
      await Hive.initFlutter();
    } else {
      await initializer();
    }
    await Hive.openBox(_boxName);
    _inited = true;
  }

  Future<List<DiaryEntry>> load() async {
    await init();
    final box = Hive.box(_boxName);
    final raw = box.get('entries');
    if (raw == null) return [];
    final list = (raw as List)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => DiaryEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> save(List<DiaryEntry> entries) async {
    await init();
    final box = Hive.box(_boxName);
    final data = entries.map((e) => e.toJson()).toList();
    await box.put('entries', data);
  }

  Future<void> upsertByPath(DiaryEntry entry) async {
    final entries = await load();
    final index = entries.indexWhere((existing) => existing.path == entry.path);
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    entries.sort((left, right) => right.date.compareTo(left.date));
    await save(entries);
  }

  Future<void> removeByPath(String path) async {
    final entries = await load();
    entries.removeWhere((entry) => entry.path == path);
    await save(entries);
  }

  Future<void> clear() async {
    await init();
    final box = Hive.box(_boxName);
    await box.put('entries', []);
  }
}
