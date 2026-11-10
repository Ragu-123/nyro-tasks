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

  static const String defaultWebAppUrl = 'https://nyro-gate-study.onrender.com';

  /// Resolves the effective bucket repository string (e.g. 'username/bucket-name')
  Future<String> getEffectiveBucketRepo({String? token}) async {
    final customBucket = await DatabaseService.instance.getHfBucket();
    String? bucket = (customBucket != null && customBucket.trim().isNotEmpty)
        ? customBucket.trim()
        : await DatabaseService.instance.getHfRepo();

    if (bucket == null || bucket.trim().isEmpty) {
      bucket = 'gate2027-nyro';
    }

    if (bucket.contains('/')) {
      return bucket.trim();
    }

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

    final user = (username != null && username.trim().isNotEmpty) ? username.trim() : 'me';
    return '$user/${bucket.trim()}';
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

  /// Programmatically create a new Storage Bucket on Hugging Face
  Future<bool> createHfBucket({
    required String token,
    required String bucketRepo,
    bool isPrivate = true,
  }) async {
    try {
      String namespace = 'me';
      String name = bucketRepo.trim();
      if (bucketRepo.contains('/')) {
        final parts = bucketRepo.trim().split('/');
        namespace = parts[0];
        name = parts[1];
      }
      final url = Uri.parse('https://huggingface.co/api/buckets/$namespace/$name');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'visibility': isPrivate ? 'private' : 'public',
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 409) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Backward-compatible alias for creating a storage repo
  Future<bool> createHfDatasetRepo({
    required String token,
    required String repoName,
    bool isPrivate = true,
  }) async {
    return await createHfBucket(token: token, bucketRepo: repoName, isPrivate: isPrivate);
  }

  // 1. Download nyro.db directly from user's Hugging Face Bucket
  Future<void> downloadCloudNyroDb({
    required String token,
    bool smartMerge = false,
    String? bucketRepo,
  }) async {
    await downloadAndRestoreAndroidDb(token: token, bucketRepo: bucketRepo);
  }

  // 2. Upload local Android database to Hugging Face as cloud backup
  Future<void> uploadAndroidDbToHub({
    required String token,
    String? bucketRepo,
  }) async {
    final targetBucket = bucketRepo ?? await getEffectiveBucketRepo(token: token);
    final localDbPath = await DatabaseService.instance.getDbPath();
    final file = File(localDbPath);
    if (!await file.exists()) {
      throw Exception('Local database file not found at $localDbPath');
    }
    final bytes = await file.readAsBytes();

    // Route 1: Push via Cloud Bridge to Hugging Face Bucket
    bool cloudBridgeSynced = false;
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
        cloudBridgeSynced = true;
      }
    } catch (_) {}

    if (cloudBridgeSynced) {
      await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
      return;
    }

    // Route 2: Push directly via Git LFS / Dataset commit to user repo
    final cleanRepo = targetBucket.contains('/') ? targetBucket : '$targetBucket';
    final sha256Hex = sha256.convert(bytes).toString();
    final size = bytes.length;

    // Step 1: Request Git LFS batch upload
    final batchUrl = Uri.parse('https://huggingface.co/datasets/$cleanRepo.git/info/lfs/objects/batch');
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
      throw Exception('Cloud backup failed (${batchResponse.statusCode}): ${batchResponse.body}');
    }

    final batchData = jsonDecode(batchResponse.body) as Map<String, dynamic>;
    final objects = batchData['objects'] as List<dynamic>?;
    if (objects == null || objects.isEmpty) {
      throw Exception('Invalid cloud storage response');
    }

    final firstObj = objects[0] as Map<String, dynamic>;
    final actions = firstObj['actions'] as Map<String, dynamic>?;

    // Step 2: Upload raw file bytes
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
        throw Exception('Cloud write failed (${putResponse.statusCode}): ${putResponse.body}');
      }
    }

    // Step 2b: Verify LFS upload
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
        throw Exception('Cloud verification failed (${verifyResponse.statusCode}): ${verifyResponse.body}');
      }
    }

    // Step 3: Commit pointer
    final commitUrl = Uri.parse('https://huggingface.co/api/datasets/$cleanRepo/commit/main');
    final ndjsonLines = [
      jsonEncode({'key': 'header', 'value': {'summary': 'Sync database backup from NYRO Tasks'}}),
      jsonEncode({
        'key': 'lfsFile',
        'value': {
          'path': 'nyro.db',
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
      throw Exception('Cloud commit failed (${commitResponse.statusCode}): ${commitResponse.body}');
    }

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }

  // 3. Download and restore database directly from Hugging Face Bucket
  Future<void> downloadAndRestoreAndroidDb({
    required String token,
    String? bucketRepo,
  }) async {
    final targetBucket = bucketRepo ?? await getEffectiveBucketRepo(token: token);

    // Primary: Download nyro.db directly from Hugging Face Bucket
    final bucketUrl = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
    var response = await http.get(bucketUrl, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    // Fallback 1: Query WebApp cloud bridge
    if (response.statusCode != 200) {
      try {
        final fbUrl = Uri.parse('$defaultWebAppUrl/api/sync/db');
        final fbRes = await http.get(fbUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
        });
        if (fbRes.statusCode == 200 && fbRes.bodyBytes.length > 500) {
          response = fbRes;
        }
      } catch (_) {}
    }

    // Fallback 2: Check dataset repo
    if (response.statusCode != 200) {
      final datasetUrl = Uri.parse('https://huggingface.co/datasets/$targetBucket/resolve/main/nyro.db');
      final dsRes = await http.get(datasetUrl, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
      if (dsRes.statusCode == 200) {
        response = dsRes;
      }
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to download database from $targetBucket (HTTP ${response.statusCode})');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_restore_nyro.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    await DatabaseService.instance.overwriteDatabase(tempPath);

    try {
      await File(tempPath).delete();
    } catch (_) {}

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }
}
