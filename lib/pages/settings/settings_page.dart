import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/pages/settings/schema_guide_page.dart';
import 'package:tasks/services/app_update_service.dart';
import 'package:tasks/services/cloud_sync_service.dart';
import 'package:tasks/services/desktop_log_server_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/utils/url_helper.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class SettingsPage extends StatefulWidget {
  final String? initialSection;

  const SettingsPage({Key? key, this.initialSection}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Cloud Sync
  final _tokenController = TextEditingController();
  final _usernameController = TextEditingController();
  final _repoController = TextEditingController();
  final _bucketController = TextEditingController();
  bool _isTestingCloud = false;

  // Log Server
  bool _serverRunning = false;
  String? _serverUrl;
  bool _autoStartServer = false;

  // App Updates
  bool _autoCheckUpdates = true;
  bool _isCheckingUpdates = false;

  // Alerts
  bool _morningBrief = true;
  String _morningBriefTime = '05:00';
  bool _revisitAlerts = true;
  bool _backlogShield = true;
  String _shieldTime = '21:30';

  // DB Stats
  int _lectureCount = 0;
  int _revisitCount = 0;
  int _quizCount = 0;
  int _mistakeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();

    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToSection(widget.initialSection!);
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _usernameController.dispose();
    _repoController.dispose();
    _bucketController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    // Cloud
    _tokenController.text = (await DatabaseService.instance.getHfToken()) ?? '';
    _usernameController.text = (await DatabaseService.instance.getHfUsername()) ?? '';
    _repoController.text = (await DatabaseService.instance.getHfRepo()) ?? '';
    _bucketController.text = (await DatabaseService.instance.getHfBucket()) ?? (await DatabaseService.instance.getHfRepo()) ?? '';

    // Server
    _serverRunning = DesktopLogServerService.instance.isRunning;
    _serverUrl = DesktopLogServerService.instance.serverUrl;
    _autoStartServer = await DatabaseService.instance.getAutoStartServer();

    // Updates
    _autoCheckUpdates = await DatabaseService.instance.getAutoCheckUpdates();

    // Alerts
    final alerts = await DatabaseService.instance.getAlertSettings();
    _morningBrief = alerts['morning_brief'] == 1;
    _morningBriefTime = alerts['morning_brief_time'] ?? '05:00';
    _revisitAlerts = alerts['revisit_alerts'] == 1;
    _backlogShield = alerts['backlog_shield'] == 1;
    _shieldTime = alerts['shield_time'] ?? '21:30';

    // DB stats
    final db = await DatabaseService.instance.database;
    final lecs = (await db.rawQuery('SELECT COUNT(*) as cnt FROM lectures')).first['cnt'] as int? ?? 0;
    final revs = (await db.rawQuery('SELECT COUNT(*) as cnt FROM revisit_items')).first['cnt'] as int? ?? 0;
    final qzs = (await db.rawQuery('SELECT COUNT(*) as cnt FROM quiz_items')).first['cnt'] as int? ?? 0;
    final msts = (await db.rawQuery('SELECT COUNT(*) as cnt FROM mistake_records')).first['cnt'] as int? ?? 0;

    if (mounted) {
      setState(() {
        _lectureCount = lecs;
        _revisitCount = revs;
        _quizCount = qzs;
        _mistakeCount = msts;
      });
    }
  }

  void _navigateToSection(String section) {
    switch (section.toLowerCase()) {
      case 'cloud':
        _openSubPage(
          title: 'Cloud Sync & Hugging Face',
          icon: Icons.cloud_sync_outlined,
          builder: (ctx) => _buildCloudSyncDetail(),
        );
        break;
      case 'server':
        _openSubPage(
          title: 'Laptop Mistake Log Server',
          icon: Icons.laptop_chromebook_rounded,
          builder: (ctx) => _buildLogServerDetail(),
        );
        break;
      case 'updates':
        _openSubPage(
          title: 'In-App Updates',
          icon: Icons.system_update_rounded,
          builder: (ctx) => _buildUpdatesDetail(),
        );
        break;
      case 'alerts':
        _openSubPage(
          title: 'Notifications & Alerts',
          icon: Icons.notifications_none_rounded,
          builder: (ctx) => _buildAlertsDetail(),
        );
        break;
      case 'schema':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const DatabaseSchemaGuidePage()));
        break;
      case 'about':
        _openSubPage(
          title: 'About & Diagnostics',
          icon: Icons.info_outline_rounded,
          builder: (ctx) => _buildAboutDetail(),
        );
        break;
    }
  }

  void _openSubPage({
    required String title,
    required IconData icon,
    required Widget Function(BuildContext) builder,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: builder(context),
        ),
      ),
    ).then((_) => _loadAllSettings());
  }

  // --- Cloud Actions ---

  Future<void> _saveCloudSettings() async {
    await DatabaseService.instance.setHfToken(_tokenController.text.trim());
    await DatabaseService.instance.setHfUsername(_usernameController.text.trim());
    await DatabaseService.instance.setHfRepo(_repoController.text.trim());
    await DatabaseService.instance.setHfBucket(_bucketController.text.trim());

    TopBanner.show(
      context,
      title: 'Settings Saved',
      message: 'Cloud Sync preferences updated.',
      icon: Icons.check_circle_outline_rounded,
      color: googleGreen,
    );
  }

  Future<void> _testCloudConnection() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      TopBanner.show(
        context,
        title: 'Missing Token',
        message: 'Please paste your Hugging Face write token.',
        icon: Icons.warning_amber_rounded,
        color: googleAmber,
      );
      return;
    }

    setState(() => _isTestingCloud = true);

    try {
      final user = await CloudSyncService.instance.whoAmI(token);
      setState(() => _isTestingCloud = false);

      if (user != null && user.isNotEmpty) {
        if (_usernameController.text.trim().isEmpty) {
          _usernameController.text = user;
          await DatabaseService.instance.setHfUsername(user);
        }
        TopBanner.show(
          context,
          title: 'Connection Verified',
          message: 'Authenticated as Hugging Face user: $user',
          icon: Icons.verified_user_rounded,
          color: googleGreen,
        );
      } else {
        TopBanner.show(
          context,
          title: 'Authentication Failed',
          message: 'Invalid Hugging Face write token.',
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    } catch (e) {
      setState(() => _isTestingCloud = false);
      TopBanner.show(
        context,
        title: 'Error Testing Token',
        message: e.toString().replaceAll('Exception: ', ''),
        icon: Icons.sync_problem_rounded,
        color: googleRed,
      );
    }
  }

  // --- Log Server Actions ---

  Future<void> _toggleLogServer(bool enable) async {
    if (enable) {
      final url = await DesktopLogServerService.instance.startServer();
      setState(() {
        _serverRunning = true;
        _serverUrl = url;
      });
      TopBanner.show(
        context,
        title: 'Laptop Server Online',
        message: 'Connect laptop to $url',
        icon: Icons.wifi_tethering_rounded,
        color: googleGreen,
      );
    } else {
      await DesktopLogServerService.instance.stopServer();
      setState(() {
        _serverRunning = false;
        _serverUrl = null;
      });
      TopBanner.show(
        context,
        title: 'Server Stopped',
        message: 'Desktop connection closed.',
        icon: Icons.portable_wifi_off_rounded,
        color: googleTextSecondary,
      );
    }
  }

  // --- In-App Updates Actions ---

  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingUpdates = true);

    try {
      final release = await AppUpdateService().checkForUpdate();
      setState(() => _isCheckingUpdates = false);

      if (release != null && release.isNewerThan(AppUpdateService.currentVersion)) {
        _showUpdateDialog(release);
      } else {
        TopBanner.show(
          context,
          title: 'Up to Date',
          message: 'You are on the latest version (v${AppUpdateService.currentVersion}).',
          icon: Icons.verified_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      setState(() => _isCheckingUpdates = false);
      TopBanner.show(
        context,
        title: 'Update Check Error',
        message: e.toString().replaceAll('Exception: ', ''),
        icon: Icons.sync_problem_rounded,
        color: googleRed,
      );
    }
  }

  void _showUpdateDialog(AppReleaseInfo release) {
    bool isDownloading = false;
    double downloadProgress = 0.0;
    String downloadText = '';
    String? downloadedFilePath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFE0E2EC), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: googleGreen.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.system_update_rounded, color: googleGreen, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Available: ${release.tagName}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                            ),
                            Text(
                              'Size: ${release.sizeDisplay} • Current: v${AppUpdateService.currentVersion}',
                              style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: googleHairline),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarkdownBody(
                            data: release.body.trim().isEmpty
                                ? '### Highlights\n* Bug fixes and performance improvements\n* Hugging Face Bucket cloud sync\n* Full-width desktop mistake reviewer'
                                : release.body,
                            selectable: true,
                            onTapLink: (text, href, title) {
                              if (href != null && href.isNotEmpty) {
                                UrlHelper.launchURL(href);
                              }
                            },
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: const TextStyle(fontSize: 12.5, color: googleTextPrimary, height: 1.4),
                              h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                              h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary),
                              h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: googleTextPrimary),
                              listBullet: const TextStyle(fontSize: 13, color: googleBlue),
                              a: const TextStyle(fontSize: 12.5, color: googleBlue, decoration: TextDecoration.underline),
                              code: TextStyle(
                                fontSize: 11.5,
                                color: Colors.purple.shade700,
                                backgroundColor: const Color(0xFFF1F3F4),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, thickness: 1, color: googleHairline),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () {
                              final tag = release.tagName;
                              UrlHelper.launchURL('https://github.com/${AppUpdateService.defaultGithubRepo}/releases/tag/$tag');
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 14, color: googleBlue),
                                  SizedBox(width: 6),
                                  Text(
                                    'View Full Release Notes on GitHub',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: googleBlue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isDownloading) ...[
                    LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null, color: googleBlue),
                    const SizedBox(height: 8),
                    Center(child: Text(downloadText, style: const TextStyle(fontSize: 11, color: googleTextSecondary))),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: isDownloading
                          ? null
                          : () {
                              if (downloadedFilePath != null) {
                                AppUpdateService().installApk(downloadedFilePath!);
                                return;
                              }

                              setSheetState(() {
                                isDownloading = true;
                                downloadText = 'Starting download...';
                              });

                              AppUpdateService().downloadAndTrack(
                                release.apkDownloadUrl,
                                onComplete: (filePath) {
                                  setSheetState(() {
                                    isDownloading = false;
                                    downloadedFilePath = filePath;
                                    downloadText = 'Download complete!';
                                  });
                                  AppUpdateService().installApk(filePath);
                                },
                              ).listen((prog) {
                                setSheetState(() {
                                  downloadProgress = prog.progress;
                                  downloadText = '${prog.receivedDisplay} / ${prog.totalDisplay} (${prog.percentInt}%)';
                                });
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: googleBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        downloadedFilePath != null ? 'Install Update Now' : (isDownloading ? 'Downloading...' : 'Download & Install Update'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Alert Settings Actions ---

  Future<void> _saveAlertSettings() async {
    await DatabaseService.instance.updateAlertSettings(
      morningBrief: _morningBrief,
      revisitAlerts: _revisitAlerts,
      backlogShield: _backlogShield,
      morningBriefTime: _morningBriefTime,
      shieldTime: _shieldTime,
    );
  }

  Future<void> _requestNotificationPermission() async {
    final granted = await NotificationService.instance.requestPermissions();
    if (mounted) {
      TopBanner.show(
        context,
        title: granted ? 'Permissions Granted' : 'Permissions Checked',
        message: granted
            ? 'Notifications & exact alarms are enabled.'
            : 'Please allow notification permissions in device settings.',
        icon: granted ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
        color: granted ? googleGreen : googleAmber,
      );
    }
  }

  Future<void> _sendTestNotification() async {
    await NotificationService.instance.showInstantNotification(
      title: 'NYRO Study Alert',
      body: 'Notifications are working! Alarms and channels are active.',
    );
    if (mounted) {
      TopBanner.show(
        context,
        title: 'Test Notification Dispatched',
        message: 'Check your status bar notification shade.',
        icon: Icons.check_circle_outline_rounded,
        color: googleBlue,
      );
    }
  }

  Future<void> _pickMorningBriefTime() async {
    final parts = _morningBriefTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 5,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() => _morningBriefTime = '$h:$m');
      await _saveAlertSettings();
    }
  }

  Future<void> _pickShieldTime() async {
    final parts = _shieldTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 21,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 30) : 30,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() => _shieldTime = '$h:$m');
      await _saveAlertSettings();
    }
  }

  // ==========================================
  // MAIN SETTINGS VIEW: CATEGORIZED TILES
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final cloudRepoSubtitle = _repoController.text.isNotEmpty
        ? 'Repo: ${_repoController.text}'
        : (_tokenController.text.isNotEmpty ? 'Token configured' : 'Not configured');

    final serverSubtitle = _serverRunning
        ? '🟢 Running on ${_serverUrl ?? "port 8080"}'
        : 'Connect laptop to log exam blunders';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [googleBlue.withOpacity(0.08), googleBlue.withOpacity(0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: googleBlue.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: googleBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, color: googleBlue, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NYRO App Preferences',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cloud tokens, LAN log server, and routine alerts',
                        style: TextStyle(fontSize: 11, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 1. Cloud Sync Tile
          _buildCategoryTile(
            icon: Icons.cloud_sync_outlined,
            iconColor: googleBlue,
            title: 'Cloud Sync & Hugging Face',
            subtitle: cloudRepoSubtitle,
            onTap: () => _navigateToSection('cloud'),
          ),

          // 2. Laptop Log Server Tile
          _buildCategoryTile(
            icon: Icons.laptop_chromebook_rounded,
            iconColor: Colors.teal,
            title: 'Laptop Mistake Log Server',
            subtitle: serverSubtitle,
            badgeWidget: _serverRunning
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                    child: const Text('ACTIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: googleGreen)),
                  )
                : null,
            onTap: () => _navigateToSection('server'),
          ),

          // 3. In-App Updates Tile
          _buildCategoryTile(
            icon: Icons.system_update_rounded,
            iconColor: googleGreen,
            title: 'In-App Updates',
            subtitle: 'v${AppUpdateService.currentVersion} • GitHub releases channel',
            onTap: () => _navigateToSection('updates'),
          ),

          // 4. Notifications & Routine Alerts Tile
          _buildCategoryTile(
            icon: Icons.notifications_none_rounded,
            iconColor: googleAmber,
            title: 'Notifications & Routine Alerts',
            subtitle: 'Morning Brief ($_morningBriefTime), Spaced Recall, Backlog Shield',
            onTap: () => _navigateToSection('alerts'),
          ),

          // 5. Database Schema & Mass Import Guide Tile
          _buildCategoryTile(
            icon: Icons.storage_rounded,
            iconColor: Colors.deepPurple,
            title: 'Database Schema & Mass Import Guide',
            subtitle: 'SQLite DDL structure & copyable JSON templates',
            onTap: () => _navigateToSection('schema'),
          ),

          // 6. About App & Diagnostics Tile
          _buildCategoryTile(
            icon: Icons.info_outline_rounded,
            iconColor: Colors.blueGrey,
            title: 'About & Diagnostics',
            subtitle: 'DB statistics, curriculum loader & reset',
            onTap: () => _navigateToSection('about'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? badgeWidget,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary),
              ),
            ),
            if (badgeWidget != null) badgeWidget,
          ],
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: googleTextSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: googleTextSecondary, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
      ),
    );
  }

  // ==========================================
  // DETAIL SUBPAGES
  // ==========================================

  // --- Detail 1: Cloud Sync ---
  Widget _buildCloudSyncDetail() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardContainer(
          children: [
            const Text('Hugging Face Write Token', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'hf_xxxxxxxxxxxxxxxxxxxxxxxx',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
              ),
            ),
            const SizedBox(height: 12),

            const Text('Hugging Face Username', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                hintText: 'e.g. username (or auto-detected from token)',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Hugging Face Storage Bucket', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                InkWell(
                  onTap: () => openExternalUrl('https://huggingface.co/new-bucket'),
                  child: const Text('Create Bucket ↗', style: TextStyle(fontSize: 11, color: googleBlue, decoration: TextDecoration.underline)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _bucketController,
              decoration: InputDecoration(
                hintText: 'e.g. gate2027-nyro or username/my-bucket',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: googleBorder)),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTestingCloud ? null : _testCloudConnection,
                    icon: _isTestingCloud
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('Test Token'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: googleBlue,
                      side: const BorderSide(color: googleBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveCloudSettings,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- Detail 2: Log Server ---
  Widget _buildLogServerDetail() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardContainer(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Local HTTP Server', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      _serverRunning ? '🟢 Running on port 8080' : '🔴 Server stopped',
                      style: TextStyle(fontSize: 12, color: _serverRunning ? googleGreen : googleTextSecondary),
                    ),
                  ],
                ),
                Switch(
                  value: _serverRunning,
                  activeColor: googleBlue,
                  onChanged: (val) => _toggleLogServer(val),
                ),
              ],
            ),
            if (_serverRunning && _serverUrl != null) ...[
              const Divider(height: 20, thickness: 1, color: googleHairline),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: googleGreen.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.link_rounded, color: googleGreen, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _serverUrl!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18, color: googleGreen),
                          tooltip: 'Copy URL',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _serverUrl!));
                            TopBanner.show(
                              context,
                              title: 'URL Copied',
                              message: 'Copied ${_serverUrl!} to clipboard.',
                              icon: Icons.check_circle_outline_rounded,
                              color: googleGreen,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFDCFCE7)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.shield_rounded, size: 14, color: googleGreen),
                                SizedBox(width: 4),
                                Text(
                                  'Public Wi-Fi Shield PIN',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: googleGreen.withOpacity(0.4)),
                              ),
                              child: Text(
                                DesktopLogServerService.instance.pairingPin,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: googleGreen,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18, color: googleGreen),
                              tooltip: 'Copy PIN',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: DesktopLogServerService.instance.pairingPin));
                                TopBanner.show(
                                  context,
                                  title: 'PIN Copied',
                                  message: '6-digit PIN copied to clipboard.',
                                  icon: Icons.shield_rounded,
                                  color: googleGreen,
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 20, color: googleBlue),
                              tooltip: 'Regenerate PIN',
                              onPressed: () {
                                setState(() {
                                  DesktopLogServerService.instance.generateNewPin();
                                });
                                TopBanner.show(
                                  context,
                                  title: 'New PIN Generated',
                                  message: 'Existing desktop connections will need this new PIN.',
                                  icon: Icons.vpn_key_rounded,
                                  color: googleBlue,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open this URL in Chrome/Edge on your laptop and enter the 6-digit PIN to securely log & review mistakes on public Wi-Fi.',
                style: TextStyle(fontSize: 11, color: googleTextSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Auto-start server on app launch', style: TextStyle(fontSize: 13)),
                Switch(
                  value: _autoStartServer,
                  activeColor: googleBlue,
                  onChanged: (val) async {
                    setState(() => _autoStartServer = val);
                    await DatabaseService.instance.setAutoStartServer(val);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- Detail 3: In-App Updates ---
  Widget _buildUpdatesDetail() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardContainer(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Version: v${AppUpdateService.currentVersion}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const Text('Repository: Ragu-123/nyro-tasks', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
                  ],
                ),
                ElevatedButton(
                  onPressed: _isCheckingUpdates ? null : _checkForUpdates,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: googleBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isCheckingUpdates
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Check Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Check for updates on app launch', style: TextStyle(fontSize: 13)),
                Switch(
                  value: _autoCheckUpdates,
                  activeColor: googleBlue,
                  onChanged: (val) async {
                    setState(() => _autoCheckUpdates = val);
                    await DatabaseService.instance.setAutoCheckUpdates(val);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- Detail 4: Alerts & Notifications ---
  Widget _buildAlertsDetail() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Android System Permissions & Diagnostics
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'PERMISSIONS & SYSTEM INTEGRATION',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
          ),
        ),
        _buildCardContainer(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: googleBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, color: googleBlue, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System Notification Access', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Required for on-time study bells and daily briefings', style: TextStyle(fontSize: 11.5, color: googleTextSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _requestNotificationPermission,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: googleBlue,
                      side: const BorderSide(color: googleBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.notifications_active_outlined, size: 16),
                    label: const Text('Grant / Verify', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sendTestNotification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send Test Alert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: googleTextSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ensure battery optimization is set to "Unrestricted" so alarms fire on time.',
                      style: TextStyle(fontSize: 11, color: googleTextSecondary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2. Daily Study Routine Schedules
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'DAILY STUDY ROUTINES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
          ),
        ),
        _buildCardContainer(
          children: [
            // Morning Brief
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickMorningBriefTime,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Morning Study Brief', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Scheduled at $_morningBriefTime AM', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit_outlined, size: 13, color: googleBlue),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Switch(
                  value: _morningBrief,
                  activeColor: googleBlue,
                  onChanged: (val) {
                    setState(() => _morningBrief = val);
                    _saveAlertSettings();
                  },
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1, color: googleHairline),

            // Spaced Recall Alerts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spaced Recall Checkpoints', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Day 1, Day 4, Day 7 due reminders', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                    ],
                  ),
                ),
                Switch(
                  value: _revisitAlerts,
                  activeColor: googleBlue,
                  onChanged: (val) {
                    setState(() => _revisitAlerts = val);
                    _saveAlertSettings();
                  },
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1, color: googleHairline),

            // Evening Backlog Shield
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickShieldTime,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Evening Backlog Shield', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Scheduled at $_shieldTime PM', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit_outlined, size: 13, color: googleBlue),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Switch(
                  value: _backlogShield,
                  activeColor: googleBlue,
                  onChanged: (val) {
                    setState(() => _backlogShield = val);
                    _saveAlertSettings();
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- Detail 5: About & Diagnostics ---
  Widget _buildAboutDetail() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardContainer(
          children: [
            const Text('NYRO Tasks for GATE 2027', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'A Google Tasks inspired study pacing, spaced retention, and blunder inoculation copilot for GATE aspirants.',
              style: TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => openExternalUrl('https://github.com/Ragu-123/nyro-tasks'),
              child: const Row(
                children: [
                  Icon(Icons.code_rounded, size: 16, color: googleBlue),
                  SizedBox(width: 6),
                  Text(
                    'https://github.com/Ragu-123/nyro-tasks ↗',
                    style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Local Record Counts:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextSecondary)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatChip('Lectures', _lectureCount),
                _buildStatChip('Revisits', _revisitCount),
                _buildStatChip('Quizzes', _quizCount),
                _buildStatChip('Mistakes', _mistakeCount),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await DatabaseService.instance.loadSampleCurriculum();
                      await _loadAllSettings();
                      TopBanner.show(
                        context,
                        title: 'Curriculum Loaded',
                        message: 'Prepackaged GATE 2027 curriculum imported.',
                        icon: Icons.check_circle_outline_rounded,
                        color: googleGreen,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: googleBlue,
                      side: const BorderSide(color: googleBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Load Sample DB', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Clear All Timetable Data?'),
                          content: const Text('This will delete all lectures, revisits, and quizzes on this device.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: googleRed, foregroundColor: Colors.white),
                              child: const Text('Clear All'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await DatabaseService.instance.clearAllTimetableData();
                        await _loadAllSettings();
                        TopBanner.show(
                          context,
                          title: 'Timetable Cleared',
                          message: 'All schedule and quiz items removed.',
                          icon: Icons.delete_outline_rounded,
                          color: googleRed,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: googleRed,
                      side: const BorderSide(color: googleRed),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Clear Timetable', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardContainer({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildStatChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text('$count', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary)),
          Text(label, style: const TextStyle(fontSize: 10, color: googleTextSecondary)),
        ],
      ),
    );
  }
}
