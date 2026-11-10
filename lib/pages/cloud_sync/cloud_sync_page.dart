import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/pages/settings/settings_page.dart';
import 'package:tasks/services/cloud_sync_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/utils/url_helper.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class CloudSyncPage extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const CloudSyncPage({Key? key, this.onDataChanged}) : super(key: key);

  @override
  _CloudSyncPageState createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  String? _token;
  String? _username;
  String? _repo;
  String? _bucket;
  String? _lastSyncedAt;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatusText = '';

  // Setup controllers for any user
  final _tokenController = TextEditingController();
  final _usernameController = TextEditingController();
  final _repoController = TextEditingController(text: 'gate2027-nyro');
  bool _createBucketInApp = false;
  bool _isSettingUp = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _usernameController.dispose();
    _repoController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final token = await DatabaseService.instance.getHfToken();
    final username = await DatabaseService.instance.getHfUsername();
    final bucket = await DatabaseService.instance.getHfBucket();
    final repo = (bucket != null && bucket.trim().isNotEmpty)
        ? bucket.trim()
        : await DatabaseService.instance.getHfRepo();
    final lastSync = await DatabaseService.instance.getConfig('last_synced_at');

    final effectiveBucket = (bucket != null && bucket.trim().isNotEmpty)
        ? bucket.trim()
        : (repo != null && repo.trim().isNotEmpty ? repo.trim() : null);

    if (mounted) {
      setState(() {
        _token = token;
        _username = username;
        _bucket = effectiveBucket;
        _repo = effectiveBucket;
        _lastSyncedAt = lastSync;
        _isLoading = false;
      });
      if (effectiveBucket != null && effectiveBucket.isNotEmpty) {
        _repoController.text = effectiveBucket;
      }
      if (token != null && token.isNotEmpty) {
        _tokenController.text = token;
      }
      if (username != null && username.isNotEmpty) {
        _usernameController.text = username;
      }
    }
  }

  Future<void> _saveFirstTimeSetup() async {
    final token = _tokenController.text.trim();
    String username = _usernameController.text.trim();
    final repo = _repoController.text.trim().isNotEmpty ? _repoController.text.trim() : 'gate2027-nyro';

    if (token.isEmpty) {
      TopBanner.show(
        context,
        title: 'Missing Token',
        message: 'Please enter your Hugging Face write token.',
        icon: Icons.warning_amber_rounded,
        color: googleRed,
      );
      return;
    }

    setState(() {
      _isSettingUp = true;
    });

    try {
      // Validate token and auto-detect username if blank
      if (username.isEmpty) {
        final detected = await CloudSyncService.instance.whoAmI(token);
        if (detected != null && detected.isNotEmpty) {
          username = detected;
        } else {
          username = 'user';
        }
      }

      final effectiveRepo = repo.contains('/') ? repo : '$username/$repo';

      // Create bucket on Hugging Face if requested
      if (_createBucketInApp) {
        await CloudSyncService.instance.createHfBucket(
          token: token,
          bucketRepo: effectiveRepo,
          isPrivate: true,
        );
      }

      await DatabaseService.instance.setHfToken(token);
      await DatabaseService.instance.setHfUsername(username);
      await DatabaseService.instance.setHfRepo(effectiveRepo);
      await DatabaseService.instance.setHfBucket(effectiveRepo);

      TopBanner.show(
        context,
        title: 'Cloud Connected',
        message: 'Hugging Face Bucket ($effectiveRepo) linked successfully.',
        icon: Icons.check_circle_outline_rounded,
        color: googleGreen,
      );

      await _loadConfig();
    } catch (e) {
      TopBanner.show(
        context,
        title: 'Setup Error',
        message: e.toString().replaceAll('Exception: ', ''),
        icon: Icons.error_outline_rounded,
        color: googleRed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSettingUp = false;
        });
      }
    }
  }

  Future<void> _uploadDatabase() async {
    if (_token == null || _token!.isEmpty) return;

    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Uploading database to Hugging Face...';
    });

    try {
      await CloudSyncService.instance.uploadAndroidDbToHub(token: _token!);

      await DatabaseService.instance.addInAppNotification(
        title: 'Database Backed Up',
        message: 'Uploaded to ${_repo ?? "Hub Bucket"}',
        type: 'CLOUD_SYNC',
      );

      TopBanner.show(
        context,
        title: 'Upload Completed',
        message: 'Study ticks and mistake records safely backed up.',
        icon: Icons.cloud_done_outlined,
        color: googleGreen,
      );

      await _loadConfig();
      widget.onDataChanged?.call();
    } catch (e) {
      TopBanner.show(
        context,
        title: 'Upload Failed',
        message: e.toString().replaceAll('Exception: ', ''),
        icon: Icons.cloud_off_outlined,
        color: googleRed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = '';
        });
      }
    }
  }

  Future<void> _restoreDatabase() async {
    if (_token == null || _token!.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restore Database from Hub?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will download your latest backed up database from Hugging Face and restore all your study progress on this device.',
          style: TextStyle(fontSize: 13, color: googleTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: googleBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Restore Now'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Restoring database from Hugging Face...';
    });

    try {
      await CloudSyncService.instance.downloadAndRestoreAndroidDb(token: _token!);

      await DatabaseService.instance.addInAppNotification(
        title: 'Database Restored',
        message: 'Downloaded from ${_repo ?? "Hub Bucket"}',
        type: 'CLOUD_SYNC',
      );

      TopBanner.show(
        context,
        title: 'Restore Completed',
        message: 'Database progress restored successfully.',
        icon: Icons.check_circle_outline_rounded,
        color: googleGreen,
      );

      await _loadConfig();
      widget.onDataChanged?.call();
    } catch (e) {
      TopBanner.show(
        context,
        title: 'Restore Failed',
        message: e.toString().replaceAll('Exception: ', ''),
        icon: Icons.error_outline_rounded,
        color: googleRed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConfigured = _token != null && _token!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Cloud Backup & Sync',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: googleTextSecondary),
            tooltip: 'Cloud Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage(initialSection: 'cloud')),
              );
              if (mounted) {
                await _loadConfig();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: googleBlue))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!isConfigured)
                  _buildFirstTimeSetupCard()
                else
                  _buildSyncDashboard(),
              ],
            ),
    );
  }

  // --- First Time Setup Form ---
  Widget _buildFirstTimeSetupCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: googleHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: googleBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.cloud_done_rounded, size: 24, color: googleBlue),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hugging Face Cloud Backup',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Use Hugging Face Storage Buckets as your personal cloud backup for study progress and mistakes.',
                          style: TextStyle(fontSize: 12, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Educational guide box for creating a bucket
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: googleBlue),
                        SizedBox(width: 6),
                        Text(
                          'How to set up your Bucket:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Get your Access Token with Write permissions.\n'
                      '2. Create a Storage Bucket on Hugging Face (choose Private).\n'
                      '3. Enter your Token and Bucket name below to connect.',
                      style: TextStyle(fontSize: 11.5, color: googleTextPrimary, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => openExternalUrl('https://huggingface.co/new-bucket'),
                          child: const Text(
                            'Create Bucket on Hugging Face ↗',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: googleBlue, decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Token Field
              const Text(
                'HUGGING FACE WRITE TOKEN',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tokenController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'hf_xxxxxxxxxxxxxxxxxxxxxxxx',
                  hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => openExternalUrl('https://huggingface.co/settings/tokens'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  child: const Text('Get Hugging Face Write Token ↗', style: TextStyle(fontSize: 11, color: googleBlue)),
                ),
              ),

              const SizedBox(height: 12),
              // Username Field
              const Text(
                'HUGGING FACE USERNAME (OPTIONAL)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  hintText: 'Leave empty to auto-detect from token',
                  hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              const SizedBox(height: 16),
              // Bucket Name Field
              const Text(
                'STORAGE BUCKET NAME',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _repoController,
                decoration: InputDecoration(
                  hintText: 'e.g. gate2027-nyro or username/my-bucket',
                  hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  helperText: 'Your private bucket storing nyro.db backup',
                  helperStyle: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Checkbox(
                    value: _createBucketInApp,
                    activeColor: googleBlue,
                    onChanged: (val) => setState(() => _createBucketInApp = val ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'Create this private bucket for me on Hugging Face',
                      style: TextStyle(fontSize: 12.5, color: googleTextPrimary),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSettingUp ? null : _saveFirstTimeSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: googleBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSettingUp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save & Connect Cloud Backup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsPage(initialSection: 'cloud')),
                    );
                    if (mounted) {
                      await _loadConfig();
                    }
                  },
                  icon: const Icon(Icons.tune_rounded, size: 16, color: googleBlue),
                  label: const Text('Configure Token & Bucket in Settings', style: TextStyle(fontSize: 12.5, color: googleBlue)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Active Sync Dashboard ---
  Widget _buildSyncDashboard() {
    String syncTimeDisplay = 'Never backed up';
    if (_lastSyncedAt != null) {
      final dt = DateTime.tryParse(_lastSyncedAt!);
      if (dt != null) {
        syncTimeDisplay = 'Last backed up: ${DateFormat('d MMM yyyy • hh:mm a').format(dt)}';
      }
    }

    final displayUser = (_username != null && _username!.isNotEmpty)
        ? '@$_username'
        : ((_bucket != null && _bucket!.contains('/'))
            ? '@${_bucket!.split('/')[0]}'
            : 'Hugging Face Hub');
    final displayBucket = (_bucket != null && _bucket!.isNotEmpty) ? _bucket! : (_repo ?? 'Storage Bucket');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connected Status Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: googleHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F0FE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_done_rounded, color: googleBlue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayUser,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: googleGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('CONNECTED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: googleGreen)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayBucket,
                      style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      syncTimeDisplay,
                      style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Link to Settings for editing tokens
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage(initialSection: 'cloud')),
              );
              if (mounted) {
                await _loadConfig();
              }
            },
            icon: const Icon(Icons.tune_rounded, size: 16, color: googleBlue),
            label: const Text('Change Token / Bucket in Settings', style: TextStyle(fontSize: 12, color: googleBlue)),
          ),
        ),
        const SizedBox(height: 16),

        if (_isSyncing) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9EE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: googleAmber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: googleAmber, strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Text(
                  _syncStatusText,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                ),
              ],
            ),
          ),
        ],

        // THE TWO PROMINENT BACKUP & RESTORE ACTIONS
        const Text(
          'CLOUD BACKUP & RESTORE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
        ),
        const SizedBox(height: 12),

        // Action 1: Upload Backup to Hub
        _buildActionCard(
          icon: Icons.cloud_upload_outlined,
          iconColor: googleBlue,
          title: 'Upload Backup to Hub',
          description: 'Upload your current study ticks, completed checkboxes, mistake notebook, and custom reminders to your private Hugging Face bucket as cloud backup.',
          buttonLabel: 'Upload Backup Now',
          onTap: _isSyncing ? null : _uploadDatabase,
        ),
        const SizedBox(height: 16),

        // Action 2: Restore DB from Hub
        _buildActionCard(
          icon: Icons.cloud_download_outlined,
          iconColor: googleGreen,
          title: 'Restore Database from Hub',
          description: 'Download your saved nyro.db backup from Hugging Face and restore all your study progress onto this phone.',
          buttonLabel: 'Restore Database Now',
          onTap: _isSyncing ? null : _restoreDatabase,
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String buttonLabel,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: googleTextSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
