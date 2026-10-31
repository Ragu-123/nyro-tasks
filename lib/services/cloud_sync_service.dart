import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tasks/data/database_service.dart';

class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._internal();
  CloudSyncService._internal();

  static const String hfBucketRepo = 'King758/gate2027-nyro';
  static const String hfAndroidDatasetRepo = 'King758/nyro-android-data';

  // 1. Download Master nyro.db from Telegram mini app bucket
  Future<void> downloadCloudNyroDb({
    required String token,
    required bool smartMerge,
  }) async {
    final url = Uri.parse('https://huggingface.co/buckets/$hfBucketRepo/resolve/nyro.db');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    if (response.statusCode != 200) {
      throw Exception('Failed to download cloud nyro.db (Status ${response.statusCode}): ${response.body}');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_cloud_nyro.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    if (smartMerge) {
      await DatabaseService.instance.smartMergeDatabase(tempPath);
    } else {
      await DatabaseService.instance.overwriteDatabase(tempPath);
    }

    // Clean up temporary file
    try {
      await File(tempPath).delete();
    } catch (_) {}
  }

  // 2. Upload local Android database to Hub as android_nyro.db
  Future<void> uploadAndroidDbToHub({required String token}) async {
    final localDbPath = await DatabaseService.instance.getDbPath();
    final bytes = await File(localDbPath).readAsBytes();
    final base64Content = base64Encode(bytes);

    final url = Uri.parse('https://huggingface.co/api/datasets/$hfAndroidDatasetRepo/commit/main');

    final lines = [
      jsonEncode({'key': 'header', 'value': {'summary': 'Sync android_nyro.db from Android Tasks app'}}),
      jsonEncode({'key': 'file', 'value': {'content': base64Content, 'path': 'android_nyro.db', 'encoding': 'base64'}})
    ];
    final payload = '${lines.join('\n')}\n';

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/x-ndjson',
      },
      body: utf8.encode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload Android DB to Hub (Status ${response.statusCode}): ${response.body}');
    }
  }

  // 3. Download and restore android_nyro.db from Hub
  Future<void> downloadAndRestoreAndroidDb({required String token}) async {
    final url = Uri.parse('https://huggingface.co/datasets/$hfAndroidDatasetRepo/resolve/main/android_nyro.db');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    if (response.statusCode != 200) {
      throw Exception('Failed to download android_nyro.db (Status ${response.statusCode}): ${response.body}');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_android_nyro.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    await DatabaseService.instance.overwriteDatabase(tempPath);

    try {
      await File(tempPath).delete();
    } catch (_) {}
  }
}
