import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/cloud_sync_service.dart';
import 'package:tasks/utils/theme.dart';

class CloudSyncModalSheet extends StatefulWidget {
  final VoidCallback onSyncCompleted;

  const CloudSyncModalSheet({
    Key? key,
    required this.onSyncCompleted,
  }) : super(key: key);

  @override
  _CloudSyncModalSheetState createState() => _CloudSyncModalSheetState();
}

class _CloudSyncModalSheetState extends State<CloudSyncModalSheet> {
  final TextEditingController _tokenController = TextEditingController();
  bool _obscureToken = true;
  String? _savedToken;
  bool _isLoadingToken = true;

  bool _isSyncing = false;
  String? _syncStatusMessage;
  String? _syncErrorMessage;
  String? _syncSuccessMessage;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final token = await DatabaseService.instance.getHfToken();
    if (mounted) {
      setState(() {
        _savedToken = token;
        if (token != null && token.isNotEmpty) {
          _tokenController.text = token;
        }
        _isLoadingToken = false;
      });
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _syncErrorMessage = 'Please enter a valid Hugging Face token');
      return;
    }
    await DatabaseService.instance.setHfToken(token);
    setState(() {
      _savedToken = token;
      _syncErrorMessage = null;
      _syncSuccessMessage = 'Token saved successfully!';
    });
  }

  Future<void> _performSyncCloudMaster({required bool smartMerge}) async {
    final token = _savedToken;
    if (token == null || token.isEmpty) {
      setState(() => _syncErrorMessage = 'Please save your Hugging Face token first.');
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = smartMerge ? 'Downloading & smart merging nyro.db...' : 'Downloading master nyro.db...';
      _syncErrorMessage = null;
      _syncSuccessMessage = null;
    });

    try {
      await CloudSyncService.instance.downloadCloudNyroDb(token: token, smartMerge: smartMerge);
      widget.onSyncCompleted();
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncSuccessMessage = smartMerge
            ? 'Cloud nyro.db smart-merged successfully! Progress preserved.'
            : 'Cloud nyro.db restored successfully!';
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncErrorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _performUploadAndroidDb() async {
    final token = _savedToken;
    if (token == null || token.isEmpty) {
      setState(() => _syncErrorMessage = 'Please save your Hugging Face token first.');
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Uploading android_nyro.db to Hub dataset...';
      _syncErrorMessage = null;
      _syncSuccessMessage = null;
    });

    try {
      await CloudSyncService.instance.uploadAndroidDbToHub(token: token);
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncSuccessMessage = 'Uploaded android_nyro.db to Hub dataset!';
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncErrorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _performRestoreAndroidDb() async {
    final token = _savedToken;
    if (token == null || token.isEmpty) {
      setState(() => _syncErrorMessage = 'Please save your Hugging Face token first.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Cloud Backup?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text(
          'This will overwrite your current local database with your latest database from Hugging Face Hub. Proceed?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: googleBlue, foregroundColor: Colors.white),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Downloading & restoring android_nyro.db...';
      _syncErrorMessage = null;
      _syncSuccessMessage = null;
    });

    try {
      await CloudSyncService.instance.downloadAndRestoreAndroidDb(token: token);
      widget.onSyncCompleted();
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncSuccessMessage = 'Local database restored from Hub backup!';
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
        _syncErrorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = _savedToken != null && _savedToken!.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E2EC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_sync_outlined, color: googleBlue, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud Sync',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: googleTextPrimary,
                        ),
                      ),
                      Text(
                        'Hugging Face Hub & Buckets',
                        style: TextStyle(fontSize: 12, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: googleTextSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Body
          Expanded(
            child: _isLoadingToken
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      // Status / Feedback Banners
                      if (_syncStatusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: googleBlue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _syncStatusMessage!,
                                  style: const TextStyle(fontSize: 13, color: googleBlue, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_syncSuccessMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: googleGreen, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _syncSuccessMessage!,
                                  style: const TextStyle(fontSize: 13, color: googleGreen, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_syncErrorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE8E6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: googleRed, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _syncErrorMessage!,
                                  style: const TextStyle(fontSize: 13, color: googleRed, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Hugging Face Token Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE0E2EC)),
                        ),
                        child: hasToken
                            ? Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE8F0FE),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.shield_outlined, color: googleBlue, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Hugging Face Auth',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: googleTextPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: googleGreen,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _savedToken!.length > 10
                                              ? '${_savedToken!.substring(0, 6)}••••••••${_savedToken!.substring(_savedToken!.length - 4)}'
                                              : '••••••••',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: googleTextSecondary,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () {
                                      setState(() => _savedToken = null);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      side: const BorderSide(color: Color(0xFFDADCE0)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('Change', style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.vpn_key_outlined, size: 18, color: googleBlue),
                                      SizedBox(width: 8),
                                      Text(
                                        'Hugging Face Access Token',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: googleTextPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Paste your personal access token (with write access) to backup and sync your database with Hub.',
                                    style: TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.3),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _tokenController,
                                    obscureText: _obscureToken,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'hf_xxxxxxxxxxxxxxxxxxxxxxxxx',
                                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA0A6)),
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      prefixIcon: const Icon(Icons.key_rounded, size: 18, color: googleTextSecondary),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                          size: 18,
                                          color: googleTextSecondary,
                                        ),
                                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFDADCE0)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFDADCE0)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: googleBlue, width: 1.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _isSyncing ? null : _saveToken,
                                        icon: const Icon(Icons.check_rounded, size: 16),
                                        label: const Text('Save Token', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: googleBlue,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),

                      const SizedBox(height: 20),

                      // SYNC OPERATIONS SECTION
                      const Text(
                        'SYNC ACTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: googleTextSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Action 1: Download & Sync Master nyro.db
                      _buildSyncCard(
                        icon: Icons.cloud_download_rounded,
                        iconColor: googleBlue,
                        title: 'Sync Master Database (nyro.db)',
                        subtitle:
                            'Download updated lectures, timetable dates, and quizzes from your Hugging Face storage bucket.',
                        actions: [
                          FilledButton.icon(
                            onPressed: (_isSyncing || !hasToken)
                                ? null
                                : () => _performSyncCloudMaster(smartMerge: true),
                            icon: const Icon(Icons.merge_type_rounded, size: 16),
                            label: const Text('Smart Merge (Safe)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: googleBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: (_isSyncing || !hasToken)
                                ? null
                                : () => _performSyncCloudMaster(smartMerge: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: googleTextSecondary,
                              side: const BorderSide(color: Color(0xFFDADCE0)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            child: const Text('Full Overwrite'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Action 2: Upload Android DB to Hub
                      _buildSyncCard(
                        icon: Icons.cloud_upload_rounded,
                        iconColor: const Color(0xFF1E8E3E),
                        title: 'Upload Android DB to Hub',
                        subtitle:
                            'Upload your current study ticks, completed checkboxes, mistake notebook, and custom reminders to your cloud bucket.',
                        actions: [
                          FilledButton.icon(
                            onPressed: (_isSyncing || !hasToken) ? null : _performUploadAndroidDb,
                            icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                            label: const Text('Upload to Hub'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E8E3E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Action 3: Restore Android DB from Hub
                      _buildSyncCard(
                        icon: Icons.settings_backup_restore_rounded,
                        iconColor: googleAmber,
                        title: 'Restore Android DB from Hub',
                        subtitle:
                            'Download your previously backed up database from your cloud bucket to restore your progress.',
                        actions: [
                          OutlinedButton.icon(
                            onPressed: (_isSyncing || !hasToken) ? null : _performRestoreAndroidDb,
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Download & Restore'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: googleTextPrimary,
                              side: const BorderSide(color: Color(0xFFDADCE0)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<Widget> actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: googleTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions,
          ),
        ],
      ),
    );
  }
}
