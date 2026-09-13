import 'dart:async';

import 'package:puck/src/core/format.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds and hands off the emergency SMS.
///
/// Puck never sends the message itself -- sending SMS silently requires
/// SEND_SMS, which is a Play-Store-restricted permission and, rightly, a hard
/// no for an app whose whole premise is restraint. Instead we deep-link into
/// the native SMS composer with the body pre-filled. One tap sends it.
///
/// That extra tap is a feature: it makes an accidental pocket-SOS recoverable.
class MessagingService {
  /// Under 160 characters so it stays a single GSM-7 segment.
  static String buildSosBody({
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime at,
  }) {
    final String coords = PuckFormat.coords(latitude, longitude);
    final String map = PuckFormat.coordsUrl(latitude, longitude);
    final String stamp = PuckFormat.shortStamp(at);
    final String acc = PuckFormat.accuracy(accuracy);

    return 'SOS - I need help. Loc: $coords (+/-$acc) $map - $stamp';
  }

  /// Opens the SMS composer. Returns false if nothing can handle the intent.
  Future<bool> openSms({
    required String recipient,
    required String body,
  }) async {
    final String cleaned = recipient.replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) return false;

    // Manual encoding: Uri.queryParameters writes spaces as '+', which some
    // SMS clients render literally. %20 is universally safe.
    final Uri uri = Uri.parse(
      'sms:$cleaned?body=${Uri.encodeComponent(body)}',
    );

    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
