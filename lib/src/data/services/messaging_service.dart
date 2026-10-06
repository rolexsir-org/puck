import 'dart:async';

import 'package:puck/src/core/format.dart';
import 'package:puck/src/l10n/puck_strings.dart';
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
  /// Four lines, in the order a human would ask for them. No greeting, no
  /// drama, no capitalised urgency -- the recipient knows the sender.
  ///
  /// [strings] is not optional and not an afterthought: the person receiving
  /// this message is very often *not* a speaker of the sender's second
  /// language. An SOS from a Spanish speaker that arrives in English is a
  /// message the recipient may not be able to read at all.
  static String buildSosBody({
    required double? latitude,
    required double? longitude,
    required double? accuracy,
    required DateTime at,
    required PuckStrings strings,
  }) {
    final String where;
    if (latitude == null || longitude == null) {
      where = strings.sosMessageNoLocation;
    } else {
      final String acc =
          accuracy == null ? '' : ' (${PuckFormat.accuracy(accuracy)})';
      where = '${PuckFormat.coordsDegrees(latitude, longitude)}$acc';
    }

    final String map = latitude == null || longitude == null
        ? ''
        : '\n${PuckFormat.coordsUrl(latitude, longitude)}';

    return '${strings.sosMessage}\n$where$map\n${strings.stamp(at)}';
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

  /// Opens the platform dialer with the emergency number pre-filled.
  ///
  /// **Never a call, always the dialer.** `tel:` maps to `ACTION_DIAL` on
  /// Android and to an unsent `tel:` URL on iOS: the number appears in the
  /// dial-pad and a human presses the call button. That preserves the same
  /// property [openSms] preserves -- a pocket cannot complete an action on its
  /// own -- while needing no permission at all (no `CALL_PHONE`, no
  /// `READ_PHONE_STATE`), which matters because a permissions prompt in the
  /// middle of an emergency is another thing that can go wrong.
  ///
  /// Returns false when the device has no dialer at all (some tablets), so the
  /// caller can say so instead of showing a dead button.
  Future<bool> dialEmergency(String number) async {
    final String cleaned = number.replaceAll(RegExp(r'[^\d+*#]'), '');
    if (cleaned.isEmpty) return false;

    final Uri uri = Uri.parse('tel:$cleaned');
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
