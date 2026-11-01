import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  // 2. Upload local Android database to Hub as android_nyro.db via Git LFS
  Future<void> uploadAndroidDbToHub({required String token}) async {
    final localDbPath = await DatabaseService.instance.getDbPath();
    final file = File(localDbPath);
    if (!await file.exists()) {
      throw Exception('Local database file not found at $localDbPath');
    }
    final bytes = await file.readAsBytes();
    final sha256Hex = sha256.convert(bytes).toString();
    final size = bytes.length;

    // Step 1: Request Git LFS batch upload
    final batchUrl = Uri.parse('https://huggingface.co/datasets/$hfAndroidDatasetRepo.git/info/lfs/objects/batch');
    final batchPayload = jsonEncode({
      'operation': 'upload',
      'transfers': ['basic'],
      'objects': [
        {
          'oid': sha256Hex,
          'size': size,
        }
      ],
    });

    final batchResponse = await http.post(
      batchUrl,
      headers: {
        'Accept': 'application/vnd.git-lfs+json',
        'Content-Type': 'application/vnd.git-lfs+json',
        'Authorization': 'Bearer ${token.trim()}',
      },
      body: batchPayload,
    );

    if (batchResponse.statusCode != 200) {
      throw Exception('Failed to initiate LFS upload (Status ${batchResponse.statusCode}): ${batchResponse.body}');
    }

    final batchData = jsonDecode(batchResponse.body) as Map<String, dynamic>;
    final objects = batchData['objects'] as List<dynamic>?;
    if (objects == null || objects.isEmpty) {
      throw Exception('Invalid LFS batch response from Hugging Face');
    }

    final firstObj = objects[0] as Map<String, dynamic>;
    final actions = firstObj['actions'] as Map<String, dynamic>?;

    // Step 2: Upload raw file bytes to storage href if upload action provided
    if (actions != null && actions.containsKey('upload')) {
      final uploadInfo = actions['upload'] as Map<String, dynamic>;
      final href = uploadInfo['href'] as String;
      final rawHeaders = uploadInfo['header'] as Map<String, dynamic>? ?? {};
      final uploadHeaders = rawHeaders.map((k, v) => MapEntry(k, v.toString()));

      final putResponse = await http.put(
        Uri.parse(href),
        headers: uploadHeaders,
        body: bytes,
      );

      if (putResponse.statusCode != 200 && putResponse.statusCode != 201) {
        throw Exception('Failed to upload DB binary to storage (Status ${putResponse.statusCode}): ${putResponse.body}');
      }
    }

    // Step 3: Commit the LFS pointer to git
    final commitUrl = Uri.parse('https://huggingface.co/api/datasets/$hfAndroidDatasetRepo/commit/main');
    final ndjsonLines = [
      jsonEncode({'key': 'header', 'value': {'summary': 'Sync android_nyro.db from Android Tasks app'}}),
      jsonEncode({
        'key': 'lfsFile',
        'value': {
          'path': 'android_nyro.db',
          'algo': 'sha256',
          'oid': sha256Hex,
          'size': size,
        }
      }),
    ];
    final commitPayload = '${ndjsonLines.join('\n')}\n';

    final commitResponse = await http.post(
      commitUrl,
      headers: {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/x-ndjson',
      },
      body: utf8.encode(commitPayload),
    );

    if (commitResponse.statusCode != 200) {
      throw Exception('Failed to commit Android DB to Hub (Status ${commitResponse.statusCode}): ${commitResponse.body}');
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
