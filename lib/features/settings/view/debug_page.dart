import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodel/settings_view_model.dart';
import '../../../../services/video_review_service.dart';

class DebugPage extends StatefulWidget {
  static const route = '/debug';
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Notification Testing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              vm.sendTestNotification();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test notification sent')));
            },
            icon: const Icon(Icons.notifications),
            label: const Text('Send Test Notification'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              vm.scheduleTestNotificationIn5Seconds();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scheduled notification for 5 seconds from now')));
            },
            icon: const Icon(Icons.schedule),
            label: const Text('Schedule Test (5 seconds)'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          const Text('Rating & Review Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _getRatingInfo(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final info = snapshot.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildInfoTile('Video Count', '${info['videoCount']} videos recorded'), _buildInfoTile('Review Completed', '${info['reviewCompleted']}'), _buildInfoTile('Next Review At', 'Video #${info['nextReviewAt']}')]);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final reviewService = VideoReviewService();
              await reviewService.resetVideoCount();
              if (mounted) {
                setState(() {});
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video count and review status reset')));
                }
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Review Count'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          const Text('Notification Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: vm.getDiagnostics(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final diagnostics = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildInfoTile('Initialized', '${diagnostics['initialized']}'), _buildInfoTile('Timezone', '${diagnostics['timezone']}'), _buildInfoTile('Notifications Enabled', '${diagnostics['androidNotificationsEnabled']}'), _buildInfoTile('Channel ID', '${diagnostics['channelId']}')],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _getRatingInfo() async {
    final reviewService = VideoReviewService();
    final videoCount = await reviewService.getVideoCount();
    final reviewCompleted = await reviewService.isReviewCompleted();

    // Calculate next review video number (every 2 videos)
    final nextReviewVideo = ((videoCount ~/ 2) + 1) * 2;
    final reviewStatusText = videoCount % 2 == 0 && videoCount > 0 ? 'Now!' : '#$nextReviewVideo';

    return {'videoCount': videoCount, 'reviewCompleted': reviewCompleted ? 'Yes ✓' : 'No', 'nextReviewAt': reviewStatusText};
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}
