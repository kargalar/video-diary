import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/model/diary_entry.dart';
import 'package:video_diary/services/export_import_service.dart';

void main() {
  group('ExportImportService', () {
    late ExportImportService service;

    setUp(() {
      service = ExportImportService();
    });

    test('validateJsonFormat returns true for valid version 1 json', () {
      const validJson = '''
      {
        "version": 1,
        "videos": [
          {"path": "videos/test.mp4", "date": "2026-01-01T00:00:00.000Z"}
        ]
      }
      ''';

      expect(service.validateJsonFormat(validJson), isTrue);
    });

    test('validateJsonFormat returns false for invalid json or version', () {
      expect(service.validateJsonFormat('invalid json'), isFalse);
      expect(service.validateJsonFormat('{"version": 2}'), isFalse);
      expect(
        service.validateJsonFormat('{"version": 1, "videos": []}'),
        isFalse,
      );
    });

    test('adds a stable id when reading legacy diary data', () {
      final json = <String, dynamic>{
        'path': 'videos/legacy.mp4',
        'date': '2026-01-01T00:00:00.000Z',
      };

      final first = DiaryEntry.fromJson(json);
      final second = DiaryEntry.fromJson(json);

      expect(first.id, startsWith('legacy-'));
      expect(second.id, first.id);
      expect(first.toJson()['id'], first.id);
    });

    test('preserves an existing diary entry id through JSON', () {
      final entry = DiaryEntry(
        id: 'entry-123',
        path: 'videos/example.mp4',
        date: DateTime.utc(2026, 1, 1),
      );

      expect(DiaryEntry.fromJson(entry.toJson()).id, 'entry-123');
    });
  });
}
