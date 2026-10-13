import '../model/diary_entry.dart';
import '../model/mood.dart';

enum DiaryStatus { initial, loading, success, error }

class DiaryState {
  final DiaryStatus status;
  final List<DiaryEntry> entries;
  final List<Mood> availableMoods;
  final Map<String, int> dailyRatings;
  final Map<String, List<Mood>> dailyMoods;
  final int currentStreak;
  final int maxStreak;
  final DateTime? lastRecordedDay;
  final String? errorMessage;

  const DiaryState({this.status = DiaryStatus.initial, this.entries = const [], this.availableMoods = const [], this.dailyRatings = const {}, this.dailyMoods = const {}, this.currentStreak = 0, this.maxStreak = 0, this.lastRecordedDay, this.errorMessage});

  DiaryState copyWith({DiaryStatus? status, List<DiaryEntry>? entries, List<Mood>? availableMoods, Map<String, int>? dailyRatings, Map<String, List<Mood>>? dailyMoods, int? currentStreak, int? maxStreak, DateTime? lastRecordedDay, String? errorMessage}) {
    return DiaryState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      availableMoods: availableMoods ?? this.availableMoods,
      dailyRatings: dailyRatings ?? this.dailyRatings,
      dailyMoods: dailyMoods ?? this.dailyMoods,
      currentStreak: currentStreak ?? this.currentStreak,
      maxStreak: maxStreak ?? this.maxStreak,
      lastRecordedDay: lastRecordedDay ?? this.lastRecordedDay,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
