import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/migration_service.dart';
import '../../../services/notification_service.dart';
import '../../settings/data/settings_repository.dart';
import '../data/diary_repository.dart';
import '../data/day_data_repository.dart';
import '../data/mood_repository.dart';
import '../model/diary_entry.dart';
import '../model/mood.dart';
import 'diary_state.dart';

class DiaryViewModel extends ChangeNotifier {
  static const _sentinel = Object();

  final DiaryRepository _repo;
  final SettingsRepository _settingsRepo;
  final DayDataRepository _dayRepo;
  final MoodRepository _moodRepo;
  final NotificationService _notificationService;

  DiaryState _state = const DiaryState();
  DiaryState get state => _state;

  // For backward compatibility during refactoring
  List<DiaryEntry> get entries => _state.entries;
  List<Mood> get availableMoods => _state.availableMoods;
  Map<String, int> get dailyRatings => _state.dailyRatings;
  Map<String, List<Mood>> get dailyMoods => _state.dailyMoods;
  int get currentStreak => _state.currentStreak;
  int get maxStreak => _state.maxStreak;
  DateTime? get lastRecordedDay => _state.lastRecordedDay;

  DiaryViewModel(this._repo, this._settingsRepo, this._dayRepo, this._moodRepo, this._notificationService) {
    MigrationService.onDataMigrated = load;
  }

  void _updateState(DiaryState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<void> load() async {
    Future.microtask(() => _updateState(_state.copyWith(status: DiaryStatus.loading)));
    try {
      var moods = await _moodRepo.load();
      final rawEntries = await _repo.load();
      final all = await _dayRepo.getAll();

      moods = _mergeCatalogWithDiscoveredMoods(moods, rawEntries, all.values);
      final entries = rawEntries.map((entry) => _syncEntryMoods(entry, moods)).toList();

      final dailyRatings = {
        for (final e in all.entries)
          if (e.value.rating != null) e.key: e.value.rating!,
      };
      final dailyMoods = {for (final e in all.entries) e.key: _syncMoodList(e.value.moods, moods)};

      _updateState(_state.copyWith(status: DiaryStatus.success, entries: entries, availableMoods: moods, dailyRatings: dailyRatings, dailyMoods: dailyMoods));

      await _moodRepo.save(moods);
      await _repo.save(entries);

      _recomputeStreak();

      // Reschedule notifications on every app launch
      final settings = await _settingsRepo.load();
      await _notificationService.rescheduleIfNeeded(settings.reminderEnabled, settings.reminderHour, settings.reminderMinute);
    } catch (e) {
      _updateState(_state.copyWith(status: DiaryStatus.error, errorMessage: e.toString()));
    }
  }

  void addEntry(DiaryEntry entry) {
    final normalized = _syncEntryMoods(entry, _state.availableMoods);
    final newEntries = [normalized, ..._state.entries];
    _updateState(_state.copyWith(entries: newEntries));
    _repo.save(newEntries);
    _recomputeDailyAverageForDay(normalized.date);
    _recomputeDailyMoodsForDay(normalized.date);
    _recomputeStreak();

    // Cancel today's notification since user just recorded
    _notificationService.cancelTodayNotification();
  }

  Future<void> upsertEntry(DiaryEntry entry) async {
    final normalized = _syncEntryMoods(entry, _state.availableMoods);
    final newEntries = List<DiaryEntry>.from(_state.entries);
    final index = newEntries.indexWhere((existing) => existing.path == normalized.path);
    if (index == -1) {
      newEntries.add(normalized);
    } else {
      newEntries[index] = normalized;
    }
    newEntries.sort((left, right) => right.date.compareTo(left.date));

    await _repo.upsertByPath(normalized);
    _updateState(_state.copyWith(entries: newEntries));
    await _recomputeDailyAverageForDay(normalized.date);
    await _recomputeDailyMoodsForDay(normalized.date);
    _recomputeStreak();
    await _notificationService.cancelTodayNotification();
  }

  Future<bool> addMood({required String emoji, required String label}) async {
    final normalizedLabel = label.trim();
    final normalizedEmoji = emoji.trim().isEmpty ? '🙂' : emoji.trim();
    if (normalizedLabel.isEmpty) return false;

    final newMood = Mood(id: Mood.createUniqueId(normalizedLabel, _state.availableMoods), emoji: normalizedEmoji, label: normalizedLabel);

    final updatedMoods = [..._state.availableMoods, newMood];
    _updateState(_state.copyWith(availableMoods: updatedMoods));
    await _moodRepo.save(updatedMoods);
    return true;
  }

  Future<bool> updateMood({required Mood original, required String emoji, required String label}) async {
    final normalizedLabel = label.trim();
    final normalizedEmoji = emoji.trim().isEmpty ? '🙂' : emoji.trim();
    if (normalizedLabel.isEmpty) return false;

    final updatedMood = original.copyWith(emoji: normalizedEmoji, label: normalizedLabel);
    final updatedCatalog = _state.availableMoods.map((mood) => mood.id == original.id ? updatedMood : mood).toList();
    final updatedEntries = _state.entries.map((entry) => _replaceMoodInEntry(entry, updatedMood)).toList();
    final updatedDailyMoods = _replaceMoodInDailyMap(_state.dailyMoods, updatedMood);

    _updateState(_state.copyWith(entries: updatedEntries, availableMoods: updatedCatalog, dailyMoods: updatedDailyMoods));
    await _moodRepo.save(updatedCatalog);
    await _repo.save(updatedEntries);
    await _persistDailyMoodKeys(updatedDailyMoods.keys, updatedDailyMoods);
    return true;
  }

  Future<bool> deleteMood(String moodId) async {
    if (!_state.availableMoods.any((mood) => mood.id == moodId)) return false;

    final updatedCatalog = _state.availableMoods.where((mood) => mood.id != moodId).toList();
    final updatedEntries = _state.entries.map((entry) => _removeMoodFromEntry(entry, moodId)).toList();
    final affectedKeys = _state.dailyMoods.entries.where((entry) => entry.value.any((mood) => mood.id == moodId)).map((entry) => entry.key).toSet();
    final updatedDailyMoods = _removeMoodFromDailyMap(_state.dailyMoods, moodId);

    _updateState(_state.copyWith(entries: updatedEntries, availableMoods: updatedCatalog, dailyMoods: updatedDailyMoods));
    await _moodRepo.save(updatedCatalog);
    await _repo.save(updatedEntries);
    await _persistDailyMoodKeys(affectedKeys, updatedDailyMoods);
    return true;
  }

  // Per-entry rating and daily average helpers
  Future<void> setRatingForEntry(String path, int? rating) async {
    final idx = _state.entries.indexWhere((e) => e.path == path);
    if (idx == -1) return;
    final old = _state.entries[idx];
    final newEntries = List<DiaryEntry>.from(_state.entries);
    newEntries[idx] = _copyEntry(old, rating: rating?.clamp(1, 5));

    _updateState(_state.copyWith(entries: newEntries));
    await _repo.save(newEntries);
    await _recomputeDailyAverageForDay(old.date);
  }

  Future<void> setDescriptionForEntry(String path, String description) async {
    final idx = _state.entries.indexWhere((e) => e.path == path);
    if (idx == -1) return;
    final old = _state.entries[idx];
    final newEntries = List<DiaryEntry>.from(_state.entries);
    newEntries[idx] = _copyEntry(old, description: description.isEmpty ? null : description);

    _updateState(_state.copyWith(entries: newEntries));
    await _repo.save(newEntries);
  }

  Future<void> setMoodsForEntry(String path, List<Mood> moods) async {
    final idx = _state.entries.indexWhere((e) => e.path == path);
    if (idx == -1) return;
    final old = _state.entries[idx];
    final newEntries = List<DiaryEntry>.from(_state.entries);
    newEntries[idx] = _copyEntry(old, moods: _syncMoodList(moods, _state.availableMoods));

    _updateState(_state.copyWith(entries: newEntries));
    await _repo.save(newEntries);
    await _recomputeDailyMoodsForDay(old.date);
  }

  Future<void> setDateForEntry(String path, DateTime newDate) async {
    final idx = _state.entries.indexWhere((e) => e.path == path);
    if (idx == -1) return;
    final old = _state.entries[idx];
    final newEntries = List<DiaryEntry>.from(_state.entries);
    newEntries[idx] = _copyEntry(old, date: newDate);

    _updateState(_state.copyWith(entries: newEntries));
    await _repo.save(newEntries);
    await _recomputeDailyAverageForDay(old.date);
    await _recomputeDailyAverageForDay(newDate);
    await _recomputeDailyMoodsForDay(old.date);
    await _recomputeDailyMoodsForDay(newDate);
    _recomputeStreak();
  }

  int? getDailyAverageRating(DateTime day) => _state.dailyRatings[_keyFor(day)];

  Future<void> clearRatingsForDay(DateTime day) async {
    final key = _keyFor(day);
    await _dayRepo.clearRating(day);

    final newEntries = List<DiaryEntry>.from(_state.entries);
    for (var i = 0; i < newEntries.length; i++) {
      final e = newEntries[i];
      if (_keyFor(e.date) == key && e.rating != null) {
        newEntries[i] = _copyEntry(e, rating: null);
      }
    }

    final newRatings = Map<String, int>.from(_state.dailyRatings)..remove(key);

    _updateState(_state.copyWith(entries: newEntries, dailyRatings: newRatings));
    await _repo.save(newEntries);
  }

  Future<void> setMoodsForDay(DateTime day, List<Mood> moods) async {
    await _dayRepo.setMoods(day, moods);
    final newMoods = Map<String, List<Mood>>.from(_state.dailyMoods)..[_keyFor(day)] = List<Mood>.from(moods);
    _updateState(_state.copyWith(dailyMoods: newMoods));
  }

  List<Mood> getMoodsForDay(DateTime day) => _state.dailyMoods[_keyFor(day)] ?? const [];

  Future<void> addMoodsForDay(DateTime day, List<Mood> moods) async {
    if (moods.isEmpty) return;
    await _dayRepo.addMoods(day, moods);
    final key = _keyFor(day);
    final merged = [
      ...(_state.dailyMoods[key] ?? const <Mood>[]),
      for (final mood in moods)
        if (!(_state.dailyMoods[key] ?? const <Mood>[]).any((existingMood) => existingMood.id == mood.id)) mood,
    ];
    final newMoods = Map<String, List<Mood>>.from(_state.dailyMoods)..[key] = merged;
    _updateState(_state.copyWith(dailyMoods: newMoods));
  }

  Future<void> renameLastRecordingWithTitle(String title) async {
    if (_state.entries.isEmpty) return;
    final latest = _state.entries.first;
    final oldFile = File(latest.path);
    if (!await oldFile.exists()) return;
    final dir = oldFile.parent.path;
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(latest.date);
    final safeTitle = title.replaceAll(RegExp(r'[^\w\- ]+'), '').replaceAll(' ', '_');
    final newName = 'diary_${stamp}_$safeTitle.mp4';
    final newPath = '$dir${Platform.pathSeparator}$newName';
    try {
      await oldFile.rename(newPath);
      final updated = _copyEntry(latest, path: newPath, title: title);

      final newEntries = List<DiaryEntry>.from(_state.entries);
      newEntries[0] = updated;
      _updateState(_state.copyWith(entries: newEntries));
      await _repo.save(newEntries);
    } catch (_) {
      // ignore
    }
  }

  Future<String?> renameByPath(String path, String newTitle) async {
    try {
      final idx = _state.entries.indexWhere((e) => e.path == path);
      if (idx == -1) return null;
      final old = _state.entries[idx];
      final oldFile = File(old.path);

      final newEntries = List<DiaryEntry>.from(_state.entries);

      if (!await oldFile.exists()) {
        newEntries[idx] = _copyEntry(old, title: newTitle);
        _updateState(_state.copyWith(entries: newEntries));
        await _repo.save(newEntries);
        return old.path;
      }

      final dir = oldFile.parent.path;
      final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(old.date);
      final safeTitle = newTitle.replaceAll(RegExp(r'[^\w\- ]+'), '').replaceAll(' ', '_');
      final newName = 'diary_${stamp}_$safeTitle.mp4';
      final newPath = '$dir${Platform.pathSeparator}$newName';
      await oldFile.rename(newPath);

      newEntries[idx] = _copyEntry(old, path: newPath, title: newTitle);
      _updateState(_state.copyWith(entries: newEntries));
      await _repo.save(newEntries);
      return newPath;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteByPath(String path) async {
    try {
      final idx = _state.entries.indexWhere((e) => e.path == path);
      if (idx == -1) return false;
      final e = _state.entries[idx];

      try {
        final f = File(e.path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
      try {
        final t = e.thumbnailPath;
        if (t != null) {
          final tf = File(t);
          if (await tf.exists()) {
            await tf.delete();
          }
        }
      } catch (_) {}

      final newEntries = List<DiaryEntry>.from(_state.entries)..removeAt(idx);
      _updateState(_state.copyWith(entries: newEntries));

      await _repo.save(newEntries);
      await _recomputeDailyAverageForDay(e.date);
      await _recomputeDailyMoodsForDay(e.date);
      _recomputeStreak();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearAll() async {
    try {
      for (final e in _state.entries) {
        try {
          final f = File(e.path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
        try {
          final t = e.thumbnailPath;
          if (t != null) {
            final tf = File(t);
            if (await tf.exists()) {
              await tf.delete();
            }
          }
        } catch (_) {}
      }

      _updateState(_state.copyWith(status: DiaryStatus.success, entries: const [], dailyRatings: const {}, dailyMoods: const {}, currentStreak: 0, maxStreak: 0, lastRecordedDay: null));
      await _repo.save([]);
      await _dayRepo.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_recorded_day');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _recomputeStreak() {
    if (_state.entries.isEmpty) {
      _updateState(_state.copyWith(currentStreak: 0, maxStreak: 0, lastRecordedDay: null));
      SharedPreferences.getInstance().then((prefs) => prefs.remove('last_recorded_day'));
      return;
    }

    final uniqueDays = <DateTime>{};
    for (final e in _state.entries) {
      uniqueDays.add(_dateOnly(e.date));
    }
    final days = uniqueDays.toList()..sort((a, b) => b.compareTo(a));
    final lastRecordedDay = days.first;

    final today = _dateOnly(DateTime.now());
    int cur = 0;
    DateTime? anchor;
    if (days.contains(today)) {
      anchor = today;
    } else {
      final yesterday = today.subtract(const Duration(days: 1));
      if (days.contains(yesterday)) {
        anchor = yesterday;
      }
    }
    if (anchor != null) {
      cur = 1;
      var next = anchor.subtract(const Duration(days: 1));
      while (days.contains(next)) {
        cur += 1;
        next = next.subtract(const Duration(days: 1));
      }
    } else {
      cur = 0;
    }

    int best = 0;
    int run = 0;
    DateTime? prev;
    for (final d in days.reversed) {
      if (prev == null) {
        run = 1;
      } else if (d.difference(prev).inDays == 1) {
        run += 1;
      } else if (d == prev) {
      } else {
        if (run > best) best = run;
        run = 1;
      }
      prev = d;
    }
    if (run > best) best = run;

    _updateState(_state.copyWith(currentStreak: cur, maxStreak: best, lastRecordedDay: lastRecordedDay));

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('last_recorded_day', lastRecordedDay.toIso8601String());
    });
  }

  Future<void> _recomputeDailyAverageForDay(DateTime day) async {
    final key = _keyFor(day);
    final sameDay = _state.entries.where((e) => _keyFor(e.date) == key && (e.rating ?? 0) > 0).toList();

    final newRatings = Map<String, int>.from(_state.dailyRatings);

    if (sameDay.isEmpty) {
      newRatings.remove(key);
      await _dayRepo.clearRating(day);
    } else {
      final avg = (sameDay.map((e) => e.rating!).reduce((a, b) => a + b) / sameDay.length).round();
      newRatings[key] = avg;
      await _dayRepo.setRating(day, avg);
    }

    _updateState(_state.copyWith(dailyRatings: newRatings));
  }

  Future<void> _recomputeDailyMoodsForDay(DateTime day) async {
    final key = _keyFor(day);
    final sameDay = _state.entries.where((e) => _keyFor(e.date) == key).toList();

    final allMoods = <String, Mood>{};
    for (final entry in sameDay) {
      if (entry.moods != null && entry.moods!.isNotEmpty) {
        for (final mood in entry.moods!) {
          allMoods[mood.id] = mood;
        }
      }
    }

    final newMoods = Map<String, List<Mood>>.from(_state.dailyMoods);

    if (allMoods.isEmpty) {
      newMoods.remove(key);
      await _dayRepo.setMoods(day, []);
    } else {
      final moodList = allMoods.values.toList();
      newMoods[key] = moodList;
      await _dayRepo.setMoods(day, moodList);
    }

    _updateState(_state.copyWith(dailyMoods: newMoods));
  }

  Future<void> setDailyAverageRating(DateTime day, int rating) async {
    final key = _keyFor(day);
    final newRatings = Map<String, int>.from(_state.dailyRatings)..[key] = rating.clamp(1, 5);
    _updateState(_state.copyWith(dailyRatings: newRatings));
    await _dayRepo.setRating(day, rating.clamp(1, 5));
  }

  DiaryEntry _copyEntry(DiaryEntry entry, {String? path, DateTime? date, Object? thumbnailPath = _sentinel, int? durationMs, int? fileBytes, Object? title = _sentinel, Object? description = _sentinel, Object? rating = _sentinel, Object? moods = _sentinel, Object? lensDirection = _sentinel}) {
    return DiaryEntry(
      path: path ?? entry.path,
      date: date ?? entry.date,
      thumbnailPath: identical(thumbnailPath, _sentinel) ? entry.thumbnailPath : thumbnailPath as String?,
      durationMs: durationMs ?? entry.durationMs,
      fileBytes: fileBytes ?? entry.fileBytes,
      title: identical(title, _sentinel) ? entry.title : title as String?,
      description: identical(description, _sentinel) ? entry.description : description as String?,
      rating: identical(rating, _sentinel) ? entry.rating : rating as int?,
      moods: identical(moods, _sentinel) ? entry.moods : moods as List<Mood>?,
      lensDirection: identical(lensDirection, _sentinel) ? entry.lensDirection : lensDirection as String?,
    );
  }

  List<Mood> _mergeCatalogWithDiscoveredMoods(List<Mood> catalog, List<DiaryEntry> entries, Iterable<DayData> dayData) {
    final merged = <Mood>[...catalog];

    void addIfMissing(Mood mood) {
      if (!merged.any((existing) => existing.id == mood.id)) {
        merged.add(mood);
      }
    }

    for (final entry in entries) {
      for (final mood in entry.moods ?? const <Mood>[]) {
        addIfMissing(mood);
      }
    }

    for (final data in dayData) {
      for (final mood in data.moods) {
        addIfMissing(mood);
      }
    }

    return merged;
  }

  DiaryEntry _syncEntryMoods(DiaryEntry entry, List<Mood> catalog) {
    return _copyEntry(entry, moods: _syncMoodList(entry.moods ?? const [], catalog));
  }

  List<Mood> _syncMoodList(List<Mood> moods, List<Mood> catalog) {
    final byId = {for (final mood in catalog) mood.id: mood};
    final synced = <Mood>[];
    for (final mood in moods) {
      final resolved = byId[mood.id] ?? mood;
      if (!synced.any((existing) => existing.id == resolved.id)) {
        synced.add(resolved);
      }
    }
    return synced;
  }

  DiaryEntry _replaceMoodInEntry(DiaryEntry entry, Mood updatedMood) {
    if (entry.moods == null || entry.moods!.isEmpty) return entry;
    final updatedMoods = entry.moods!.map((mood) => mood.id == updatedMood.id ? updatedMood : mood).toList();
    return _copyEntry(entry, moods: updatedMoods);
  }

  DiaryEntry _removeMoodFromEntry(DiaryEntry entry, String moodId) {
    if (entry.moods == null || entry.moods!.isEmpty) return entry;
    final updatedMoods = entry.moods!.where((mood) => mood.id != moodId).toList();
    return _copyEntry(entry, moods: updatedMoods);
  }

  Map<String, List<Mood>> _replaceMoodInDailyMap(Map<String, List<Mood>> source, Mood updatedMood) {
    return {for (final entry in source.entries) entry.key: entry.value.map((mood) => mood.id == updatedMood.id ? updatedMood : mood).toList()};
  }

  Map<String, List<Mood>> _removeMoodFromDailyMap(Map<String, List<Mood>> source, String moodId) {
    final updated = <String, List<Mood>>{};
    for (final entry in source.entries) {
      final filtered = entry.value.where((mood) => mood.id != moodId).toList();
      if (filtered.isNotEmpty) {
        updated[entry.key] = filtered;
      }
    }
    return updated;
  }

  Future<void> _persistDailyMoodKeys(Iterable<String> keys, Map<String, List<Mood>> dailyMoodsMap) async {
    for (final key in keys.toSet()) {
      await _dayRepo.setMoods(_dateFromKey(key), dailyMoodsMap[key] ?? const []);
    }
  }

  DateTime _dateFromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime(int.tryParse(parts[0]) ?? DateTime.now().year, int.tryParse(parts[1]) ?? DateTime.now().month, int.tryParse(parts[2]) ?? DateTime.now().day);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  String _keyFor(DateTime d) {
    final dd = _dateOnly(d);
    return '${dd.year}-${dd.month.toString().padLeft(2, '0')}-${dd.day.toString().padLeft(2, '0')}';
  }
}
