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
  static const String defaultDatasetRepo = 'nyro-android-data';

  Future<String> getEffectiveDatasetRepo({String? token}) async {
    final customRepo = await DatabaseService.instance.getHfRepo();
    String repo = (customRepo != null && customRepo.trim().isNotEmpty)
        ? customRepo.trim()
        : defaultDatasetRepo;

    // If repo already includes owner/repo, return directly
    if (repo.contains('/')) {
      return repo;
    }

    // Resolve owner username
    String? username = await DatabaseService.instance.getHfUsername();
    if (username == null || username.trim().isEmpty) {
      final effectiveToken = token ?? await DatabaseService.instance.getHfToken();
      if (effectiveToken != null && effectiveToken.trim().isNotEmpty) {
        try {
          username = await whoAmI(effectiveToken);
          if (username != null && username.isNotEmpty) {
            await DatabaseService.instance.setHfUsername(username);
          }
        } catch (_) {}
      }
    }

    final effectiveUser = (username != null && username.trim().isNotEmpty)
        ? username.trim()
        : 'King758';

    return '$effectiveUser/$repo';
  }

  Future<String> getEffectiveBucketRepo() async {
    final customBucket = await DatabaseService.instance.getHfBucket();
    if (customBucket != null && customBucket.trim().isNotEmpty) {
      return customBucket.trim();
    }
    return defaultBucketRepo;
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

  /// Create a new Dataset repository on Hugging Face if not exists
  Future<bool> createHfDatasetRepo({
    required String token,
    required String repoName,
    bool isPrivate = true,
  }) async {
    final url = Uri.parse('https://huggingface.co/api/repos/create');
    final cleanRepoName = repoName.contains('/') ? repoName.split('/').last : repoName;

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': cleanRepoName,
          'type': 'dataset',
          'private': isPrivate,
        }),
      );

      // 200 or 201 means created; 409 means already exists (which is success)
      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 409) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  // 1. Download Master nyro.db from Telegram mini app bucket
  Future<void> downloadCloudNyroDb({
    required String token,
    required bool smartMerge,
    String? bucketRepo,
  }) async {
    final targetBucket = bucketRepo ?? await getEffectiveBucketRepo();
    final url = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
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

    try {
      await File(tempPath).delete();
    } catch (_) {}
  }

  // 2. Upload local Android database to Hub as android_nyro.db via Git LFS
  Future<void> uploadAndroidDbToHub({
    required String token,
    String? datasetRepo,
  }) async {
    final targetRepo = datasetRepo ?? await getEffectiveDatasetRepo(token: token);
    final localDbPath = await DatabaseService.instance.getDbPath();
    final file = File(localDbPath);
    if (!await file.exists()) {
      throw Exception('Local database file not found at $localDbPath');
    }
    final bytes = await file.readAsBytes();
    final sha256Hex = sha256.convert(bytes).toString();
    final size = bytes.length;

    // Ensure dataset repo exists (or 409 already exists)
    await createHfDatasetRepo(
      token: token,
      repoName: targetRepo,
      isPrivate: true,
    );

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
      throw Exception('Invalid LFS batch response from Hugging Face');
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

    // Step 2b: Verify LFS upload if verify action provided (MANDATORY on Hugging Face S3 LFS!)
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

  // 3. Download and restore android_nyro.db from Hub (with fallback to bucket nyro.db)
  Future<void> downloadAndRestoreAndroidDb({
    required String token,
    String? datasetRepo,
  }) async {
    final targetRepo = datasetRepo ?? await getEffectiveDatasetRepo(token: token);
    final targetBucket = await getEffectiveBucketRepo();

    // Primary: Download android_nyro.db from dataset repo
    final datasetUrl = Uri.parse('https://huggingface.co/datasets/$targetRepo/resolve/main/android_nyro.db');
    var response = await http.get(datasetUrl, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    // Fallback: If dataset android_nyro.db returns 404, download master nyro.db from bucket
    if (response.statusCode != 200) {
      final bucketUrl = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
      response = await http.get(bucketUrl, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to download database from $targetRepo or $targetBucket (Status ${response.statusCode})');
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
