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
  String? _lastSyncedAt;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatusText = '';

  // First-time setup controllers
  final _tokenController = TextEditingController();
  final _usernameController = TextEditingController(text: 'King758');
  final _repoController = TextEditingController(text: 'King758/gate2027-nyro');
  bool _createNewRepo = false;
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
    final repo = await DatabaseService.instance.getHfRepo();
    final lastSync = await DatabaseService.instance.getConfig('last_synced_at');

    if (mounted) {
      setState(() {
        _token = token;
        _username = username;
        _repo = repo;
        _lastSyncedAt = lastSync;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFirstTimeSetup() async {
    final token = _tokenController.text.trim();
    String username = _usernameController.text.trim();
    final repo = _repoController.text.trim();

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

      // Create repo if requested
      if (_createNewRepo) {
        await CloudSyncService.instance.createHfDatasetRepo(
          token: token,
          repoName: effectiveRepo,
          isPrivate: true,
        );
      }

      await DatabaseService.instance.setHfToken(token);
      await DatabaseService.instance.setHfUsername(username);
      await DatabaseService.instance.setHfRepo(effectiveRepo);

      TopBanner.show(
        context,
        title: 'Cloud Connected',
        message: 'Hugging Face repository linked successfully.',
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
        message: 'Uploaded to ${_repo ?? "Hub"}',
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

  Future<void> _smartSyncFromBucket() async {
    if (_token == null || _token!.isEmpty) return;

    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Smart merging master nyro.db from Hugging Face Bucket...';
    });

    try {
      await CloudSyncService.instance.downloadCloudNyroDb(
        token: _token!,
        smartMerge: true,
      );

      await DatabaseService.instance.addInAppNotification(
        title: 'Bucket Smart Sync',
        message: 'Merged master nyro.db from ${_repo ?? "King758/gate2027-nyro"}',
        type: 'CLOUD_SYNC',
      );

      TopBanner.show(
        context,
        title: 'Smart Sync Completed',
        message: 'Master cloud database merged without losing your local progress.',
        icon: Icons.sync_rounded,
        color: googleGreen,
      );

      await _loadConfig();
      widget.onDataChanged?.call();
    } catch (e) {
      TopBanner.show(
        context,
        title: 'Sync Failed',
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
        message: 'Downloaded from ${_repo ?? "Hub"}',
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
          'Cloud Sync',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isConfigured)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: googleTextSecondary),
              tooltip: 'Cloud Settings',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage(initialSection: 'cloud')),
                );
                _loadConfig();
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
                      color: const Color(0xFFFFE082).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🤗', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hugging Face Bucket Setup',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Connect your private storage bucket (King758/gate2027-nyro) to sync study data across devices.',
                          style: TextStyle(fontSize: 12, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
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
                'HUGGING FACE USERNAME',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  hintText: 'e.g. King758',
                  hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              const SizedBox(height: 16),
              // Repository Selection
              const Text(
                'HUGGING FACE BUCKET',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _repoController,
                decoration: InputDecoration(
                  hintText: 'King758/gate2027-nyro',
                  hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  helperText: 'Your private bucket storing nyro.db (e.g. King758/gate2027-nyro)',
                  helperStyle: const TextStyle(fontSize: 11),
                ),
              ),

              const SizedBox(height: 24),
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
                      : const Text('Save & Connect Cloud Hub', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
    String syncTimeDisplay = 'Never synced';
    if (_lastSyncedAt != null) {
      final dt = DateTime.tryParse(_lastSyncedAt!);
      if (dt != null) {
        syncTimeDisplay = 'Last synced: ${DateFormat('d MMM yyyy • hh:mm a').format(dt)}';
      }
    }

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
                          _username != null && _username!.isNotEmpty ? '@$_username' : 'Hugging Face Hub',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: googleGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('ACTIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: googleGreen)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _repo ?? 'nyro-android-data',
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
              _loadConfig();
            },
            icon: const Icon(Icons.tune_rounded, size: 16, color: googleBlue),
            label: const Text('Modify Token / Username in Settings ⚙️', style: TextStyle(fontSize: 12, color: googleBlue)),
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

        // BUCKET SYNC ACTIONS
        const Text(
          'HUGGING FACE BUCKET ACTIONS',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
        ),
        const SizedBox(height: 12),

        // Action 1: Smart Sync & Merge from Bucket
        _buildActionCard(
          icon: Icons.sync_rounded,
          iconColor: googleBlue,
          title: 'Smart Sync from Bucket',
          description: 'Pulls the master nyro.db from your private Hugging Face Bucket (King758/gate2027-nyro) and smart merges study progress without losing your local changes.',
          buttonLabel: 'Smart Sync from Bucket',
          onTap: _isSyncing ? null : _smartSyncFromBucket,
        ),
        const SizedBox(height: 16),

        // Action 2: Upload DB to Bucket
        _buildActionCard(
          icon: Icons.cloud_upload_outlined,
          iconColor: googleAmber,
          title: 'Upload DB to Bucket',
          description: 'Pushes your local database (ticks, mistakes, reminders) to Hugging Face Bucket King758/gate2027-nyro to keep all devices in sync.',
          buttonLabel: 'Upload DB to Bucket',
          onTap: _isSyncing ? null : _uploadDatabase,
        ),
        const SizedBox(height: 16),

        // Action 3: Restore DB from Bucket
        _buildActionCard(
          icon: Icons.cloud_download_outlined,
          iconColor: googleGreen,
          title: 'Full Restore from Bucket',
          description: 'Downloads the master nyro.db from Hugging Face Bucket and completely restores your study database on this phone.',
          buttonLabel: 'Restore DB from Bucket',
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
