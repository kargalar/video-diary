import 'dart:convert';
import 'dart:io';

import 'recording_session.dart';

typedef RecordingRootProvider = Future<Directory> Function();

/// Stores recording session manifests in the app’s private storage.
class RecordingSessionStore {
  RecordingSessionStore({required RecordingRootProvider rootProvider})
    : _rootProvider = rootProvider;

  static const _manifestName = 'session.json';
  static const _temporaryManifestName = 'session.json.tmp';

  final RecordingRootProvider _rootProvider;

  Future<void> save(RecordingSession session) async {
    final sessionDirectory = await _sessionDirectory(session.sessionId);
    await sessionDirectory.create(recursive: true);

    final temporaryFile = File(
      _join(sessionDirectory.path, _temporaryManifestName),
    );
    final manifestFile = File(_join(sessionDirectory.path, _manifestName));
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }

    await temporaryFile.writeAsString(
      jsonEncode(session.toJson()),
      flush: true,
    );
    await temporaryFile.rename(manifestFile.path);
  }

  Future<RecordingSession?> load(String sessionId) async {
    final sessionDirectory = await _sessionDirectory(sessionId);
    return _loadManifest(File(_join(sessionDirectory.path, _manifestName)));
  }

  Future<List<RecordingSession>> loadAll() async {
    final root = await _rootProvider();
    if (!await root.exists()) return const [];

    final sessions = <RecordingSession>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final session = await _loadManifest(
        File(_join(entity.path, _manifestName)),
      );
      if (session != null) sessions.add(session);
    }
    sessions.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return sessions;
  }

  Future<void> delete(String sessionId) async {
    final sessionDirectory = await _sessionDirectory(sessionId);
    if (await sessionDirectory.exists()) {
      await sessionDirectory.delete(recursive: true);
    }
  }

  Future<RecordingSession?> _loadManifest(File manifest) async {
    if (!await manifest.exists()) return null;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return RecordingSession.fromJson(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<Directory> _sessionDirectory(String sessionId) async {
    _validateSessionId(sessionId);
    final root = await _rootProvider();
    return Directory(_join(root.path, sessionId));
  }
}

void _validateSessionId(String sessionId) {
  if (sessionId.isEmpty ||
      sessionId == '.' ||
      sessionId == '..' ||
      sessionId.contains('/') ||
      sessionId.contains(r'\')) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'must be a safe file name',
    );
  }
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
