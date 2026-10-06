import 'package:url_launcher/url_launcher.dart';

/// The one channel a stranger has to tell the maker that something is wrong.
///
/// Puck has no accounts, no analytics and no crash reporting -- by design --
/// which leaves it with no way at all to hear about a bug. A `mailto:` with
/// the app version and four lines of diagnostics is the smallest honest
/// answer: it costs nothing, it needs no server, and the person sending it can
/// read every word before they do.
///
/// What it must never contain: the device ID, a location, a question the user
/// typed earlier, or anything else they did not put in the mail themselves.
abstract final class FeedbackService {
  /// Puck's one address. Not a form, not an API -- mail.
  static const String address = 'puck@rolexsir.org';

  static Uri mailUri({required String subject, required String body}) {
    return Uri(
      scheme: 'mailto',
      path: address,
      query: _encodeQuery(<String, String>{
        'subject': subject,
        'body': body,
      }),
    );
  }

  /// Opens the user's mail app. Returns false when there is none, so the
  /// screen can say so instead of appearing to do nothing.
  static Future<bool> openMail({
    required String subject,
    required String body,
  }) async {
    final Uri uri = mailUri(subject: subject, body: body);
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// `Uri(queryParameters:)` writes spaces as '+', which some mail clients
  /// render literally in the body. %20 is universally safe, so the query is
  /// encoded by hand -- same reasoning as the SMS body in [MessagingService].
  static String _encodeQuery(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
