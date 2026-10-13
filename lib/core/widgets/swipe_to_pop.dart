import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Swipe direction for [SwipeToPop].
enum SwipeDirection {
  /// Swipe from left to right (positive velocity).
  leftToRight,

  /// Swipe from right to left (negative velocity).
  rightToLeft,
}

/// Wraps [child] with a horizontal swipe gesture.
///
/// When the user swipes past [velocityThreshold], [onSwipe] is called.
/// [onSwipe] is intentionally async so the caller can show a confirmation
/// dialog or run any cleanup before actually navigating away.
class SwipeToPop extends StatelessWidget {
  final Widget child;

  /// Called when the swipe gesture is triggered.
  /// Return normally to allow the action; you can also ignore it inside the
  /// callback to cancel (e.g. when the user taps "Cancel" in a dialog).
  final Future<void> Function() onSwipe;

  /// Which direction triggers the gesture. Defaults to [SwipeDirection.leftToRight].
  final SwipeDirection direction;

  /// Minimum fling speed (px/s) that triggers the pop. Defaults to 300.
  final double velocityThreshold;

  const SwipeToPop({super.key, required this.child, required this.onSwipe, this.direction = SwipeDirection.leftToRight, this.velocityThreshold = 300});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final triggered = direction == SwipeDirection.leftToRight ? velocity > velocityThreshold : velocity < -velocityThreshold;
        if (triggered) {
          // Schedule after the current frame to avoid the
          // '!_debugDuringDeviceUpdate' assertion in mouse_tracker.
          SchedulerBinding.instance.addPostFrameCallback((_) => onSwipe());
        }
      },
      child: child,
    );
  }
}
