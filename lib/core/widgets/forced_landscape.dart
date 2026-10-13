import 'package:flutter/material.dart';

/// Keeps the device in portrait but renders [child] as if the screen were
/// landscape by rotating the content 90° clockwise.
///
/// MediaQuery inside the child is patched so that `size.width` and
/// `size.height` report the swapped (landscape) dimensions.
class ForcedLandscape extends StatelessWidget {
  final Widget child;

  /// Quarter‐turns to rotate.  1 = 90° CCW (landscape‐left feel when holding
  /// phone naturally).  Use -1 for 90° CW (landscape‐right).
  final int quarterTurns;

  const ForcedLandscape({super.key, required this.child, this.quarterTurns = 1});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final portrait = mq.size;
    // Swap width ↔ height so children see landscape dimensions.
    final landscapeSize = Size(portrait.height, portrait.width);

    return RotatedBox(
      quarterTurns: quarterTurns,
      child: MediaQuery(
        data: mq.copyWith(size: landscapeSize),
        child: SizedBox(width: landscapeSize.width, height: landscapeSize.height, child: child),
      ),
    );
  }
}
