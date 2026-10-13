import 'dart:async';

import 'package:flutter/material.dart';

typedef RecordingTimerClock = DateTime Function();

class RecordingTimer extends StatefulWidget {
  const RecordingTimer({
    super.key,
    required this.recordedDuration,
    required this.activeSegmentStartedAt,
    RecordingTimerClock? now,
  }) : now = now ?? DateTime.now;

  final Duration recordedDuration;
  final DateTime? activeSegmentStartedAt;
  final RecordingTimerClock now;

  @override
  State<RecordingTimer> createState() => _RecordingTimerState();
}

class _RecordingTimerState extends State<RecordingTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.activeSegmentStartedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _formatDuration(_displayedDuration());
    return Container(
      key: const ValueKey('recording_timer'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fiber_manual_record,
            color: Colors.redAccent,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Duration _displayedDuration() {
    final startedAt = widget.activeSegmentStartedAt;
    if (startedAt == null) return widget.recordedDuration;
    final activeDuration = widget.now().difference(startedAt);
    if (activeDuration.isNegative) return widget.recordedDuration;
    return widget.recordedDuration + activeDuration;
  }
}

String _formatDuration(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
