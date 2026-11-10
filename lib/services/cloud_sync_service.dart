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

  static const String defaultBucketRepo = 'King758/gate2027-nyro';
  static const String defaultDatasetRepo = 'King758/nyro-android-data';
  static const String defaultWebAppUrl = 'https://nyro-gate-study.onrender.com';

  Future<String> getEffectiveBucketRepo() async {
    final customBucket = await DatabaseService.instance.getHfBucket();
    if (customBucket != null && customBucket.trim().isNotEmpty) {
      return customBucket.trim();
    }
    return defaultBucketRepo;
  }

  Future<String> getEffectiveDatasetRepo({String? token}) async {
    final customRepo = await DatabaseService.instance.getHfRepo();
    if (customRepo != null && customRepo.trim().isNotEmpty) {
      final r = customRepo.trim();
      return r.contains('/') ? r : 'King758/$r';
    }
    return defaultDatasetRepo;
  }

  /// Verify user token and return HF username
  Future<String?> whoAmI(String token) async {
    try {
      final url = Uri.parse('https://huggingface.co/api/whoami-v2');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['name'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // 1. Download Master nyro.db directly from Hugging Face Bucket
  Future<void> downloadCloudNyroDb({
    required String token,
    required bool smartMerge,
    String? bucketRepo,
  }) async {
    final targetBucket = bucketRepo ?? await getEffectiveBucketRepo();
    final url = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
    
    http.Response? response;
    try {
      response = await http.get(url, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
    } catch (_) {}

    // Fallback: If direct bucket resolve fails, query WebApp API
    if (response == null || response.statusCode != 200) {
      try {
        final fallbackUrl = Uri.parse('$defaultWebAppUrl/api/sync/db');
        final fbRes = await http.get(fallbackUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
        });
        if (fbRes.statusCode == 200 && fbRes.bodyBytes.length > 500) {
          response = fbRes;
        }
      } catch (_) {}
    }

    if (response == null || response.statusCode != 200) {
      final errBody = response?.body ?? 'Network unreachable';
      throw Exception('Failed to download cloud nyro.db from bucket $targetBucket: $errBody');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_cloud_nyro.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    if (smartMerge) {
      await DatabaseService.instance.smartMergeDatabase(tempPath);
    } else {
      await DatabaseService.instance.overwriteDatabase(tempPath);
    }

    try {
      await File(tempPath).delete();
    } catch (_) {}

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }

  // 2. Upload local Android database to Hugging Face Bucket
  Future<void> uploadAndroidDbToHub({
    required String token,
    String? bucketRepo,
  }) async {
    final targetBucket = bucketRepo ?? await getEffectiveBucketRepo();
    final localDbPath = await DatabaseService.instance.getDbPath();
    final file = File(localDbPath);
    if (!await file.exists()) {
      throw Exception('Local database file not found at $localDbPath');
    }
    final bytes = await file.readAsBytes();

    // Route 1: Push via WebApp Cloud Bridge to Hugging Face Bucket
    bool webAppSynced = false;
    try {
      final uploadUri = Uri.parse('$defaultWebAppUrl/api/sync/upload');
      final request = http.MultipartRequest('POST', uploadUri);
      request.headers['Authorization'] = 'Bearer ${token.trim()}';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'nyro.db',
      ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      final res = await http.Response.fromStream(streamedResponse);
      if (res.statusCode == 200) {
        webAppSynced = true;
      }
    } catch (_) {}

    if (webAppSynced) {
      await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
      return;
    }

    // Route 2: Fallback to existing Dataset repo (King758/nyro-android-data) via Git LFS
    final targetRepo = await getEffectiveDatasetRepo(token: token);
    final sha256Hex = sha256.convert(bytes).toString();
    final size = bytes.length;

    // Step 1: Request Git LFS batch upload
    final batchUrl = Uri.parse('https://huggingface.co/datasets/$targetRepo.git/info/lfs/objects/batch');
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
      throw Exception('LFS batch negotiation failed (${batchResponse.statusCode}): ${batchResponse.body}');
    }

    final batchData = jsonDecode(batchResponse.body) as Map<String, dynamic>;
    final objects = batchData['objects'] as List<dynamic>?;
    if (objects == null || objects.isEmpty) {
      throw Exception('Invalid LFS response from Hugging Face');
    }

    final firstObj = objects[0] as Map<String, dynamic>;
    final actions = firstObj['actions'] as Map<String, dynamic>?;

    // Step 2: Upload raw file bytes if upload action provided
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
        throw Exception('Storage upload failed (${putResponse.statusCode}): ${putResponse.body}');
      }
    }

    // Step 2b: Verify LFS upload if verify action provided
    if (actions != null && actions.containsKey('verify')) {
      final verifyInfo = actions['verify'] as Map<String, dynamic>;
      final verifyHref = verifyInfo['href'] as String;
      final rawHeaders = verifyInfo['header'] as Map<String, dynamic>? ?? {};
      final verifyHeaders = rawHeaders.map((k, v) => MapEntry(k, v.toString()));
      verifyHeaders['Content-Type'] = 'application/vnd.git-lfs+json';

      final verifyResponse = await http.post(
        Uri.parse(verifyHref),
        headers: verifyHeaders,
        body: jsonEncode({
          'oid': sha256Hex,
          'size': size,
        }),
      );

      if (verifyResponse.statusCode != 200) {
        throw Exception('LFS verification failed (${verifyResponse.statusCode}): ${verifyResponse.body}');
      }
    }

    // Step 3: Commit the LFS pointer to git
    final commitUrl = Uri.parse('https://huggingface.co/api/datasets/$targetRepo/commit/main');
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
      throw Exception('Commit failed (${commitResponse.statusCode}): ${commitResponse.body}');
    }

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }

  // 3. Download and restore android_nyro.db (with fallback to bucket nyro.db)
  Future<void> downloadAndRestoreAndroidDb({
    required String token,
    String? datasetRepo,
  }) async {
    final targetBucket = await getEffectiveBucketRepo();
    final targetRepo = datasetRepo ?? await getEffectiveDatasetRepo(token: token);

    // Primary: Download nyro.db directly from Hugging Face Bucket
    final bucketUrl = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
    var response = await http.get(bucketUrl, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    // Secondary: Download from dataset repo if bucket is empty
    if (response.statusCode != 200) {
      final datasetUrl = Uri.parse('https://huggingface.co/datasets/$targetRepo/resolve/main/android_nyro.db');
      response = await http.get(datasetUrl, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to download database from $targetBucket or $targetRepo (Status ${response.statusCode})');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_android_nyro.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    await DatabaseService.instance.overwriteDatabase(tempPath);

    try {
      await File(tempPath).delete();
    } catch (_) {}

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }
}
