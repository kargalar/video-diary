import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests a review from the user after recording videos.
/// Requests a review every two recordings until the user has reviewed the app.
class VideoReviewService {
  static const String _videoCountKey = 'recorded_video_count';
  static const String _reviewCompletedKey = 'review_completed';

  // Number of recordings between review prompts.
  static const int _reviewRequestInterval = 2;

  final InAppReview _inAppReview = InAppReview.instance;

  /// Increments the recording count and requests a review when appropriate.
  Future<void> incrementVideoCountAndRequestReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check whether the user has completed a review.
      final reviewCompleted = prefs.getBool(_reviewCompletedKey) ?? false;

      if (reviewCompleted) {
        // The user has reviewed the app; only increment the counter.
        final currentCount = prefs.getInt(_videoCountKey) ?? 0;
        await prefs.setInt(_videoCountKey, currentCount + 1);
        return;
      }

      // Get the current recording count.
      final currentCount = prefs.getInt(_videoCountKey) ?? 0;
      final newCount = currentCount + 1;

      // Save the updated count.
      await prefs.setInt(_videoCountKey, newCount);

      // Request a review every two recordings.
      if (newCount % _reviewRequestInterval == 0) {
        await _requestReview();
      }
    } catch (e) {
      // Continue silently if an error occurs.
      debugPrint('VideoReviewService: Error updating the recording count: $e');
    }
  }

  /// Shows the review dialog.
  Future<void> _requestReview() async {
    try {
      // Check whether in-app reviews are available on this device.
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
      }
    } catch (e) {
      debugPrint('VideoReviewService: Error requesting an in-app review: $e');
    }
  }

  /// Resets the recording count and review state for testing.
  Future<void> resetVideoCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_videoCountKey);
      await prefs.remove(_reviewCompletedKey);
    } catch (e) {
      debugPrint('VideoReviewService: Error resetting the review state: $e');
    }
  }

  /// Returns the current recording count.
  Future<int> getVideoCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_videoCountKey) ?? 0;
    } catch (e) {
      debugPrint('VideoReviewService: Error reading the recording count: $e');
      return 0;
    }
  }

  /// Checks whether the user has completed a review.
  Future<bool> isReviewCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_reviewCompletedKey) ?? false;
    } catch (e) {
      debugPrint('VideoReviewService: Error checking review completion: $e');
      return false;
    }
  }

  /// Marks the review as completed.
  /// Call this method after the user leaves a store review.
  Future<void> markReviewAsCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reviewCompletedKey, true);
    } catch (e) {
      debugPrint('VideoReviewService: Error saving review completion: $e');
    }
  }
}
