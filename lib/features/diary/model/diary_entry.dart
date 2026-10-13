import 'dart:math';

import 'mood.dart';

class DiaryEntry {
  final String id; // stable identity across exports and devices
  final String path; // absolute file path
  final DateTime date; // date of recording
  final String? thumbnailPath; // local thumbnail file
  final int? durationMs; // video duration in milliseconds
  final int? fileBytes; // file size in bytes
  final String? title; // user provided title
  final String? description; // video description/notes
  final int? rating; // per-video rating 1..5
  final List<Mood>? moods; // mood tags for this entry
  final String? lensDirection; // 'front' or 'back'

  DiaryEntry({
    String? id,
    required this.path,
    required this.date,
    this.thumbnailPath,
    this.durationMs,
    this.fileBytes,
    this.title,
    this.description,
    this.rating,
    this.moods,
    this.lensDirection,
  }) : id = id ?? _generateEntryId();

  DiaryEntry copyWith({
    String? id,
    String? path,
    DateTime? date,
    String? thumbnailPath,
    int? durationMs,
    int? fileBytes,
    String? title,
    String? description,
    int? rating,
    List<Mood>? moods,
    String? lensDirection,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      path: path ?? this.path,
      date: date ?? this.date,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      durationMs: durationMs ?? this.durationMs,
      fileBytes: fileBytes ?? this.fileBytes,
      title: title ?? this.title,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      moods: moods ?? this.moods,
      lensDirection: lensDirection ?? this.lensDirection,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'date': date.toIso8601String(),
    'thumbnailPath': thumbnailPath,
    'durationMs': durationMs,
    'fileBytes': fileBytes,
    'title': title,
    'description': description,
    'rating': rating,
    'moods': moods?.map((m) => m.toJson()).toList(),
    'lensDirection': lensDirection,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: _idFromJson(json),
    path: json['path'] as String,
    date: DateTime.parse(json['date'] as String),
    thumbnailPath: json['thumbnailPath'] as String?,
    durationMs: (json['durationMs'] as num?)?.toInt(),
    fileBytes: (json['fileBytes'] as num?)?.toInt(),
    title: json['title'] as String?,
    description: json['description'] as String?,
    rating: (json['rating'] as num?)?.toInt(),
    moods: (json['moods'] as List<dynamic>?)
        ?.map(Mood.fromDynamic)
        .whereType<Mood>()
        .toList(),
    lensDirection: json['lensDirection'] as String?,
  );
}

String _generateEntryId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String _idFromJson(Map<String, dynamic> json) {
  final storedId = json['id'];
  if (storedId is String && storedId.isNotEmpty) return storedId;

  // Older records had no ID. Derive one from immutable legacy fields so the
  // same old record receives the same ID every time it is loaded.
  final fingerprint = '${json['path'] ?? ''}|${json['date'] ?? ''}';
  var hash = 2166136261;
  for (final codeUnit in fingerprint.codeUnits) {
    hash = ((hash ^ codeUnit) * 16777619) & 0xffffffff;
  }
  return 'legacy-${hash.toRadixString(16).padLeft(8, '0')}';
}
