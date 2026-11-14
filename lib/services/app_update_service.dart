import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final String apkDownloadUrl;
  final int apkSizeBytes;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
  });

  String get versionClean => tagName.replaceFirst(RegExp(r'^[vV]'), '');

  String get sizeDisplay {
    if (apkSizeBytes <= 0) return 'Unknown size';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  bool isNewerThan(String currentVersion) {
    try {
      final curClean = currentVersion.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final remClean = versionClean.trim();
      if (curClean == remClean) return false;

      final curCore = curClean.split('+').first;
      final remCore = remClean.split('+').first;

      final curParts = curCore.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final remoteParts = remCore.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      final cMajor = curParts.isNotEmpty ? curParts[0] : 0;
      final cMinor = curParts.length > 1 ? curParts[1] : 0;
      final cPatch = curParts.length > 2 ? curParts[2] : 0;

      final rMajor = remoteParts.isNotEmpty ? remoteParts[0] : 0;
      final rMinor = remoteParts.length > 1 ? remoteParts[1] : 0;
      final rPatch = remoteParts.length > 2 ? remoteParts[2] : 0;

      if (rMajor > cMajor) return true;
      if (rMajor < cMajor) return false;
      if (rMinor > cMinor) return true;
      if (rMinor < cMinor) return false;
      if (rPatch > cPatch) return true;
      if (rPatch < cPatch) return false;

      // If semantic versions match, compare build numbers if present (e.g. +6 vs +5)
      final curBuild = curClean.contains('+') ? int.tryParse(curClean.split('+').last) ?? 0 : 0;
      final remBuild = remClean.contains('+') ? int.tryParse(remClean.split('+').last) ?? 0 : 0;
      if (remBuild > curBuild) return true;

      return false;
    } catch (_) {
      return false;
    }
  }

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? 'v1.0.0';
    final name = json['name'] as String? ?? 'NYRO Tasks Update';
    final body = json['body'] as String? ?? 'No release notes provided.';
    final publishedAtStr = json['published_at'] as String?;
    final publishedAt = publishedAtStr != null ? DateTime.tryParse(publishedAtStr) ?? DateTime.now() : DateTime.now();

    final assets = json['assets'] as List<dynamic>? ?? [];
    String? downloadUrl;
    int size = 0;

    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final assetName = (asset['name'] as String? ?? '').toLowerCase();
        if (assetName.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          size = (asset['size'] as num?)?.toInt() ?? 0;
          if (assetName.contains('app-release') || assetName.contains('tasks') || assetName.contains('nyro')) {
            break; // Preferred asset match
          }
        }
      }
    }

    if (downloadUrl == null) {
      throw Exception('No APK binary found in GitHub release assets.');
    }

    return AppReleaseInfo(
      tagName: tagName,
      name: name,
      body: body,
      publishedAt: publishedAt,
      apkDownloadUrl: downloadUrl,
      apkSizeBytes: size,
    );
  }
}

class AppUpdateProgress {
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final bool isCompleted;
  final String? error;

  const AppUpdateProgress({
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    this.isCompleted = false,
    this.error,
  });

  String get receivedDisplay => '${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  String get totalDisplay => totalBytes > 0 ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '...';
  int get percentInt => (progress * 100).clamp(0, 100).toInt();
}

class AppUpdateService {
  static const String currentVersion = '1.0.12';
  static const String defaultGithubRepo = 'Ragu-123/nyro-tasks';
  static const MethodChannel _nativeChannel = MethodChannel('io.github.thelazyindian.tasks/native');

  static AppUpdateService? _instance;
  factory AppUpdateService() => _instance ??= AppUpdateService._();
  AppUpdateService._();

  String get releaseApiUrl => 'https://api.github.com/repos/$defaultGithubRepo/releases/latest';

  // Check GitHub releases for newer version
  Future<AppReleaseInfo?> checkForUpdate() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(releaseApiUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'nyro-tasks-updater');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode == 404) {
        return null; // No releases published yet
      }
      if (response.statusCode != 200) {
        throw Exception('GitHub API responded with status ${response.statusCode}');
      }

      final bodyStr = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> data = jsonDecode(bodyStr);
      return AppReleaseInfo.fromJson(data);
    } catch (e) {
      debugPrint('Check update error: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  // Stream APK download and return downloaded file path upon completion
  Stream<AppUpdateProgress> downloadAndTrack(
    String downloadUrl, {
    required Function(String filePath) onComplete,
  }) async* {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 25);

    try {
      String cacheDirPath;
      try {
        final nativeDir = await _nativeChannel.invokeMethod<String>('getAppCacheDir');
        if (nativeDir != null && nativeDir.isNotEmpty) {
          cacheDirPath = nativeDir;
        } else {
          final dir = await getTemporaryDirectory();
          cacheDirPath = dir.path;
        }
      } catch (_) {
        final dir = await getTemporaryDirectory();
        cacheDirPath = dir.path;
      }

      final targetFile = File('$cacheDirPath/nyro_tasks_update.apk');

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      // Resolve HTTP redirects (GitHub release downloads redirect to AWS S3)
      Uri currentUri = Uri.parse(downloadUrl);
      HttpClientResponse? response;
      int redirects = 0;

      while (redirects < 6) {
        final request = await client.getUrl(currentUri);
        request.headers.set('User-Agent', 'nyro-tasks-updater');
        request.followRedirects = false;
        response = await request.close();

        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            currentUri = Uri.parse(location);
            redirects++;
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != 200) {
        yield AppUpdateProgress(
          progress: 0,
          receivedBytes: 0,
          totalBytes: 0,
          error: 'Download failed (HTTP ${response?.statusCode})',
        );
        return;
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        final progress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
        yield AppUpdateProgress(
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        );
      }

      await sink.flush();
      await sink.close();

      yield AppUpdateProgress(
        progress: 1.0,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        isCompleted: true,
      );

      onComplete(targetFile.path);
    } catch (e) {
      yield AppUpdateProgress(
        progress: 0,
        receivedBytes: 0,
        totalBytes: 0,
        error: e.toString(),
      );
    } finally {
      client.close();
    }
  }

  Future<bool> canRequestPackageInstalls() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openInstallUnknownAppsSettings() async {
    try {
      await _nativeChannel.invokeMethod<void>('openInstallUnknownAppsSettings');
    } catch (_) {}
  }

  // Launch native package installer
  Future<bool> installApk(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      debugPrint('Install APK error: $e');
      return false;
    }
  }
}
