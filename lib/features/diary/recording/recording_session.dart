const _notProvided = Object();

/// Immutable session state stored on disk to safely recover an interrupted recording.
///
class RecordingSession {
  RecordingSession({
    required this.sessionId,
    required this.createdAt,
    required this.finalPath,
    required List<String> pendingSegmentPaths,
    required this.activeSegmentPath,
    required this.lensDirection,
    required this.resumePending,
    required this.entryRegistered,
    required this.accumulatedDurationMs,
  }) : pendingSegmentPaths = List.unmodifiable(pendingSegmentPaths);

  factory RecordingSession.create({
    required String sessionId,
    required DateTime createdAt,
    required String finalPath,
    required String lensDirection,
  }) {
    return RecordingSession(
      sessionId: sessionId,
      createdAt: createdAt,
      finalPath: finalPath,
      pendingSegmentPaths: const [],
      activeSegmentPath: null,
      lensDirection: lensDirection,
      resumePending: false,
      entryRegistered: false,
      accumulatedDurationMs: 0,
    );
  }

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    final createdAtText = _requiredString(json, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtText);
    if (createdAt == null) {
      throw FormatException('Invalid createdAt: $createdAtText');
    }

    final pendingSegments = json['pendingSegmentPaths'];
    if (pendingSegments is! List ||
        pendingSegments.any((item) => item is! String)) {
      throw const FormatException('pendingSegmentPaths must be a string list');
    }

    final activeSegment = json['activeSegmentPath'];
    if (activeSegment != null && activeSegment is! String) {
      throw const FormatException('activeSegmentPath must be a string or null');
    }

    return RecordingSession(
      sessionId: _requiredString(json, 'sessionId'),
      createdAt: createdAt,
      finalPath: _requiredString(json, 'finalPath'),
      pendingSegmentPaths: pendingSegments.cast<String>(),
      activeSegmentPath: activeSegment as String?,
      lensDirection: _requiredString(json, 'lensDirection'),
      resumePending: _requiredBool(json, 'resumePending'),
      entryRegistered: _requiredBool(json, 'entryRegistered'),
      accumulatedDurationMs: _requiredInt(json, 'accumulatedDurationMs'),
    );
  }

  final String sessionId;
  final DateTime createdAt;
  final String finalPath;
  final List<String> pendingSegmentPaths;
  final String? activeSegmentPath;
  final String lensDirection;
  final bool resumePending;
  final bool entryRegistered;
  final int accumulatedDurationMs;

  RecordingSession copyWith({
    String? sessionId,
    DateTime? createdAt,
    String? finalPath,
    List<String>? pendingSegmentPaths,
    Object? activeSegmentPath = _notProvided,
    String? lensDirection,
    bool? resumePending,
    bool? entryRegistered,
    int? accumulatedDurationMs,
  }) {
    if (!identical(activeSegmentPath, _notProvided) &&
        activeSegmentPath != null &&
        activeSegmentPath is! String) {
      throw ArgumentError.value(
        activeSegmentPath,
        'activeSegmentPath',
        'must be a String or null',
      );
    }

    return RecordingSession(
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      finalPath: finalPath ?? this.finalPath,
      pendingSegmentPaths: pendingSegmentPaths ?? this.pendingSegmentPaths,
      activeSegmentPath: identical(activeSegmentPath, _notProvided)
          ? this.activeSegmentPath
          : activeSegmentPath as String?,
      lensDirection: lensDirection ?? this.lensDirection,
      resumePending: resumePending ?? this.resumePending,
      entryRegistered: entryRegistered ?? this.entryRegistered,
      accumulatedDurationMs:
          accumulatedDurationMs ?? this.accumulatedDurationMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'createdAt': createdAt.toIso8601String(),
    'finalPath': finalPath,
    'pendingSegmentPaths': pendingSegmentPaths,
    'activeSegmentPath': activeSegmentPath,
    'lensDirection': lensDirection,
    'resumePending': resumePending,
    'entryRegistered': entryRegistered,
    'accumulatedDurationMs': accumulatedDurationMs,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecordingSession &&
            sessionId == other.sessionId &&
            createdAt == other.createdAt &&
            finalPath == other.finalPath &&
            _listsEqual(pendingSegmentPaths, other.pendingSegmentPaths) &&
            activeSegmentPath == other.activeSegmentPath &&
            lensDirection == other.lensDirection &&
            resumePending == other.resumePending &&
            entryRegistered == other.entryRegistered &&
            accumulatedDurationMs == other.accumulatedDurationMs;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    createdAt,
    finalPath,
    Object.hashAll(pendingSegmentPaths),
    activeSegmentPath,
    lensDirection,
    resumePending,
    entryRegistered,
    accumulatedDurationMs,
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a bool');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative int');
  }
  return value;
}

bool _listsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
