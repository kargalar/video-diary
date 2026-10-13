import '../../features/diary/data/day_data_repository.dart';
import '../../features/diary/data/diary_repository.dart';
import '../../features/diary/data/mood_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../services/migration_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import 'recording_dependencies.dart';

/// A simple service locator for dependency injection.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late final DiaryRepository diaryRepository;
  late final SettingsRepository settingsRepository;
  late final StorageService storageService;
  late final VideoService videoService;
  late final DayDataRepository dayDataRepository;
  late final MoodRepository moodRepository;
  late final NotificationService notificationService;
  late final RecordingDependencies recordingDependencies;

  Future<void> setup() async {
    diaryRepository = DiaryRepository();
    settingsRepository = SettingsRepository();
    storageService = StorageService();
    videoService = VideoService();
    dayDataRepository = DayDataRepository();
    moodRepository = MoodRepository();
    notificationService = NotificationService();

    await diaryRepository.init();
    await dayDataRepository.init();
    await moodRepository.init();
    await notificationService.init();

    recordingDependencies = await buildRecordingDependencies(
      storageService: storageService,
      diaryRepository: diaryRepository,
      videoService: videoService,
      settingsRepository: settingsRepository,
    );
    await recordingDependencies.recoveryService.recover();

    // Run silent migration in the background
    final migrationService = MigrationService(diaryRepository, settingsRepository, storageService, videoService);
    migrationService.runSilentMigration();
  }
}

final sl = ServiceLocator();
