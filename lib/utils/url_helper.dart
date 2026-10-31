import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openExternalUrl(String? urlString) async {
  if (urlString == null || urlString.trim().isEmpty) return;
  try {
    final trimmed = urlString.trim();
    final uri = Uri.parse(trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  } catch (e) {
    debugPrint('Error launching URL ($urlString): $e');
  }
}
