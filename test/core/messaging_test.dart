import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/services/messaging_service.dart';

void main() {
  group('the emergency SMS body', () {
    test('reads like a person, in the order a person asks', () {
      final String body = MessagingService.buildSosBody(
        latitude: 34.052234,
        longitude: -118.243685,
        accuracy: 12,
        at: DateTime(2026, 1, 15, 15, 14),
      );

      expect(
        body,
        'I need help.\n'
        '34.0522°N, 118.2437°W (±12m)\n'
        'maps.google.com/?q=34.0522,-118.2437\n'
        '3:14 PM · Wed Jan 15',
      );
    });

    test('without a GPS fix, it says so instead of inventing coordinates', () {
      final String body = MessagingService.buildSosBody(
        latitude: null,
        longitude: null,
        accuracy: null,
        at: DateTime(2026, 1, 15, 15, 14),
      );

      expect(body, startsWith('I need help.\nLocation unavailable'));
      expect(body.contains('maps.google.com'), isFalse);
      expect(body.endsWith('3:14 PM · Wed Jan 15'), isTrue);
    });
  });
}
