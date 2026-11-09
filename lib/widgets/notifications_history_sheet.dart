import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';

class NotificationsHistorySheet extends StatefulWidget {
  const NotificationsHistorySheet({Key? key}) : super(key: key);

  @override
  _NotificationsHistorySheetState createState() => _NotificationsHistorySheetState();
}

class _NotificationsHistorySheetState extends State<NotificationsHistorySheet> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final list = await DatabaseService.instance.getInAppNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    await DatabaseService.instance.clearInAppNotifications();
    _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E2EC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_active_outlined, color: googleBlue, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Notifications History',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                      ),
                    ),
                  ],
                ),
                if (_notifications.isNotEmpty)
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear all', style: TextStyle(color: googleRed, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 16, thickness: 1, color: googleHairline),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 48, color: googleBorder.withOpacity(0.8)),
                            const SizedBox(height: 12),
                            const Text(
                              'No recent notifications',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextSecondary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Test blunder logs, sync events, and study alerts will appear here.',
                              style: TextStyle(fontSize: 12, color: googleTextSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _notifications.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: googleHairline),
                        itemBuilder: (context, index) {
                          final item = _notifications[index];
                          final title = item['title'] as String? ?? 'Notification';
                          final message = item['message'] as String? ?? '';
                          final type = item['type'] as String? ?? 'INFO';
                          final createdAtStr = item['created_at'] as String?;

                          DateTime? dt;
                          if (createdAtStr != null) {
                            dt = DateTime.tryParse(createdAtStr);
                          }
                          final timeDisplay = dt != null ? DateFormat('d MMM • hh:mm a').format(dt) : '';

                          IconData icon = Icons.info_outline_rounded;
                          Color color = googleBlue;

                          if (type == 'MISTAKE_LOG') {
                            icon = Icons.laptop_chromebook_rounded;
                            color = googleAmber;
                          } else if (type == 'CLOUD_SYNC') {
                            icon = Icons.cloud_done_outlined;
                            color = googleGreen;
                          } else if (type == 'ALERT') {
                            icon = Icons.alarm_rounded;
                            color = googleBlue;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, color: color, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            title,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                          ),
                                          if (timeDisplay.isNotEmpty)
                                            Text(
                                              timeDisplay,
                                              style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        message,
                                        style: const TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
