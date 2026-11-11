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
    String targetBucket = bucketRepo ?? await getEffectiveBucketRepo(token: token);
    if (!targetBucket.contains('/')) {
      targetBucket = await getEffectiveBucketRepo(token: token);
    }

    // Security & Credential Isolation: Export a sanitized copy with tokens and private keys stripped
    final sanitizedDbPath = await DatabaseService.instance.exportSanitizedDatabaseForCloudUpload();
    try {
      final file = File(sanitizedDbPath);
      if (!await file.exists()) {
        throw Exception('Sanitized database export file not found');
      }
      final bytes = await file.readAsBytes();
      final cleanRepo = targetBucket.trim();
      final b64 = base64Encode(bytes);

      // Route 1: Push via Cloud Bridge to Hugging Face Bucket
      bool cloudBridgeSynced = false;
      try {
        final uploadUri = Uri.parse('$defaultWebAppUrl/api/sync/upload');
        final request = http.MultipartRequest('POST', uploadUri);
        request.headers['Authorization'] = 'Bearer ${token.trim()}';
        request.headers['X-HF-Bucket'] = cleanRepo;
        request.fields['bucket'] = cleanRepo;
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'nyro.db',
        ));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
        final res = await http.Response.fromStream(streamedResponse);
        if (res.statusCode == 200) {
          cloudBridgeSynced = true;
        }
      } catch (_) {}

      // Fallback trigger: WebApp /api/sync endpoint
      if (!cloudBridgeSynced) {
        try {
          final syncUri = Uri.parse('$defaultWebAppUrl/api/sync');
          final syncRes = await http.post(
            syncUri,
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Content-Type': 'application/json',
              'X-HF-Bucket': cleanRepo,
            },
            body: jsonEncode({'bucket': cleanRepo}),
          ).timeout(const Duration(seconds: 35));
          if (syncRes.statusCode == 200) {
            final body = jsonDecode(syncRes.body);
            if (body['synced'] == true) {
              cloudBridgeSynced = true;
            }
          }
        } catch (_) {}
      }

      if (cloudBridgeSynced) {
        await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
        return;
      }

      // Route 2: Check if target is a dataset repo (instant commit without LFS)
      bool isDataset = false;
      try {
        final dsCheckUrl = Uri.parse('https://huggingface.co/api/datasets/$cleanRepo');
        final dsCheckRes = await http.get(dsCheckUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
        }).timeout(const Duration(seconds: 10));
        if (dsCheckRes.statusCode == 200) {
          isDataset = true;
        }
      } catch (_) {}

      if (isDataset) {
        final commitUrl = Uri.parse('https://huggingface.co/api/datasets/$cleanRepo/commit/main');
        final ndjsonLines = [
          jsonEncode({'key': 'header', 'value': {'summary': 'Sync database backup from NYRO Tasks'}}),
          jsonEncode({
            'key': 'file',
            'value': {
              'content': b64,
              'path': 'nyro.db',
              'encoding': 'base64',
            }
          }),
          jsonEncode({
            'key': 'file',
            'value': {
              'content': b64,
              'path': 'android_nyro.db',
              'encoding': 'base64',
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
        ).timeout(const Duration(seconds: 45));

        if (commitResponse.statusCode == 200) {
          await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
          return;
        } else {
          throw Exception('Dataset commit failed (${commitResponse.statusCode}): ${commitResponse.body}');
        }
      }

      // Route 3: Check fallback dataset repo if configured
      final fallbackRepo = await DatabaseService.instance.getHfRepo();
      if (fallbackRepo != null && fallbackRepo.trim().isNotEmpty && fallbackRepo.trim() != cleanRepo) {
        final fbClean = fallbackRepo.contains('/') ? fallbackRepo.trim() : fallbackRepo.trim();
        try {
          final dsCheckUrl = Uri.parse('https://huggingface.co/api/datasets/$fbClean');
          final dsCheckRes = await http.get(dsCheckUrl, headers: {
            'Authorization': 'Bearer ${token.trim()}',
          }).timeout(const Duration(seconds: 10));
          if (dsCheckRes.statusCode == 200) {
            final commitUrl = Uri.parse('https://huggingface.co/api/datasets/$fbClean/commit/main');
            final ndjsonLines = [
              jsonEncode({'key': 'header', 'value': {'summary': 'Sync database backup from NYRO Tasks'}}),
              jsonEncode({
                'key': 'file',
                'value': {
                  'content': b64,
                  'path': 'nyro.db',
                  'encoding': 'base64',
                }
              }),
              jsonEncode({
                'key': 'file',
                'value': {
                  'content': b64,
                  'path': 'android_nyro.db',
                  'encoding': 'base64',
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
            ).timeout(const Duration(seconds: 45));

            if (commitResponse.statusCode == 200) {
              await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
              return;
            }
          }
        } catch (_) {}
      }

      // Check if target is a bucket
      bool isBucket = false;
      try {
        final bucketCheckUrl = Uri.parse('https://huggingface.co/api/buckets/$cleanRepo');
        final bCheckRes = await http.get(bucketCheckUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
        }).timeout(const Duration(seconds: 10));
        if (bCheckRes.statusCode == 200 || bCheckRes.statusCode == 302) {
          isBucket = true;
        }
      } catch (_) {}

      final customBucket = await DatabaseService.instance.getHfBucket();
      if (isBucket || (customBucket != null && customBucket.trim().isNotEmpty) || cleanRepo.contains('bucket')) {
        throw Exception('Cloud sync bridge to bucket timed out. Please try again in a few moments.');
      }

      throw Exception(
        'Cloud backup to "$cleanRepo" could not complete. Please verify your Hugging Face write token and bucket/dataset configuration.',
      );
    } finally {
      try {
        await File(sanitizedDbPath).delete();
      } catch (_) {}
    }
  }

  // 3. Download and restore database directly from Hugging Face Bucket or Dataset
  Future<void> downloadAndRestoreAndroidDb({
    required String token,
    String? bucketRepo,
  }) async {
    String targetBucket = bucketRepo ?? await getEffectiveBucketRepo(token: token);
    if (!targetBucket.contains('/')) {
      targetBucket = await getEffectiveBucketRepo(token: token);
    }

    // Primary: Download nyro.db directly from Hugging Face Bucket
    final bucketUrl = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/nyro.db');
    var response = await http.get(bucketUrl, headers: {
      'Authorization': 'Bearer ${token.trim()}',
    });

    // Primary 1b: Download android_nyro.db from Hugging Face Bucket
    if (response.statusCode != 200) {
      final bucketAndroidUrl = Uri.parse('https://huggingface.co/buckets/$targetBucket/resolve/android_nyro.db');
      final bRes = await http.get(bucketAndroidUrl, headers: {
        'Authorization': 'Bearer ${token.trim()}',
      });
      if (bRes.statusCode == 200) {
        response = bRes;
      }
    }

    // Fallback 1: Query WebApp cloud bridge
    if (response.statusCode != 200) {
      try {
        final fbUrl = Uri.parse('$defaultWebAppUrl/api/sync/db');
        final fbRes = await http.get(fbUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'X-HF-Bucket': targetBucket,
        }).timeout(const Duration(seconds: 60));
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
      } else {
        final datasetAndroidUrl = Uri.parse('https://huggingface.co/datasets/$targetBucket/resolve/main/android_nyro.db');
        final dsAndroidRes = await http.get(datasetAndroidUrl, headers: {
          'Authorization': 'Bearer ${token.trim()}',
        });
        if (dsAndroidRes.statusCode == 200) {
          response = dsAndroidRes;
        }
      }
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw Exception('No backup file found in "$targetBucket" (HTTP 404). Please upload a backup first.');
      }
      throw Exception('Failed to download database from $targetBucket (HTTP ${response.statusCode})');
    }

    // Security check: Validate SQLite format 3 header (first 16 bytes: "SQLite format 3\000")
    if (response.bodyBytes.length < 100) {
      throw Exception('Downloaded backup is too small to be a valid SQLite database.');
    }
    final headerStr = String.fromCharCodes(response.bodyBytes.sublist(0, 15));
    if (headerStr != 'SQLite format 3') {
      throw Exception('Downloaded file is not a valid SQLite database format.');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'temp_restore_nyro_${DateTime.now().millisecondsSinceEpoch}.db');
    await File(tempPath).writeAsBytes(response.bodyBytes, flush: true);

    await DatabaseService.instance.overwriteDatabase(tempPath);

    try {
      await File(tempPath).delete();
    } catch (_) {}

    await DatabaseService.instance.setConfig('last_synced_at', DateTime.now().toIso8601String());
  }
}
