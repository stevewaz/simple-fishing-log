import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands a coordinate to the platform's own maps app for driving directions back to a spot —
/// Apple Maps on iOS (as the Swift app did), Google Maps everywhere else (Android, web).
Future<bool> openDirections({required double latitude, required double longitude, String? label}) {
  final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final coordinate = '$latitude,$longitude';
  final uri = isIOS
      ? Uri.https('maps.apple.com', '/', {
          'daddr': coordinate,
          'dirflg': 'd',
          if (label != null && label.isNotEmpty) 'q': label,
        })
      : Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': coordinate});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
