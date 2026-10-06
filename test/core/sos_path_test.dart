import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/data/services/emergency_numbers.dart';
import 'package:puck/src/data/services/location_service.dart';
import 'package:puck/src/data/services/messaging_service.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/features/puck/puck_gesture_recognizer.dart';
import 'package:puck/src/l10n/puck_strings.dart';
import 'package:puck/src/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The emergency path, tested where it can actually fail.
//
// The interesting failures in SOS are not the happy path -- they are the
// states a phone is really in when someone holds the button: the GPS is off,
// the fix has not landed, there is no contact configured, there is no SMS app,
// there is no dialer, or the phone is in a bag. Each of those used to (or
// could) end in silence, which is the one outcome this path may not produce.
//
// Everything here runs against the real `PuckController` through its real
// public entry points, with the platform replaced at the provider seam. No
// device, no plugins, no network.
// The note above stays a doc comment on the file rather than on the first
// declaration: `library;` (unnamed) is not accepted by every parser this repo
// is checked with, and the alternative -- attaching a paragraph about the
// whole file to a fake SMS composer -- is worse.

/// The SMS composer. [openSms] is faked -- opening a real composer is not
/// possible or wanted in a test -- but [dialEmergency] is deliberately left
/// real: what the service does when the platform has no dialer is one of the
/// behaviours under test, and it does it without needing a device.
class _FakeSms extends MessagingService {
  _FakeSms({this.canOpen = true});

  bool canOpen;
  final List<String> bodies = <String>[];
  final List<String> recipients = <String>[];

  @override
  Future<bool> openSms({
    required String recipient,
    required String body,
  }) async {
    recipients.add(recipient);
    bodies.add(body);
    return canOpen;
  }
}

/// A GPS that never answers until the test lets it. This is the cold-fix
/// case, and the one that used to lose the message entirely.
class _BlockedFix extends LocationService {
  final Completer<void> release = Completer<void>();

  @override
  Future<Position?> current({
    Duration timeout = PuckConstants.locationTimeout,
  }) async {
    await release.future;
    return null;
  }
}

/// A GPS with no fix to give: the permission was refused, or the radio is
/// switched off. Same observable result, same null.
class _NoFix extends LocationService {
  @override
  Future<Position?> current({
    Duration timeout = PuckConstants.locationTimeout,
  }) async => null;
}

void main() {
  final PuckStrings es = PuckStrings.forLocale(const Locale('es'));

  Future<(ProviderContainer, SettingsRepository)> harness({
    required MessagingService sms,
    required LocationService location,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container =
        ProviderContainer(overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      messagingServiceProvider.overrideWithValue(sms),
      locationServiceProvider.overrideWithValue(location),
    ]);
    addTearDown(container.dispose);
    return (container, container.read(settingsProvider));
  }

  Future<PuckController> armed(
    WidgetTester tester, {
    required MessagingService sms,
    required LocationService location,
    String contact = '+15550100',
  }) async {
    final (ProviderContainer container, SettingsRepository settings) =
        await harness(sms: sms, location: location);
    if (contact.isNotEmpty) await settings.setContactPhone(contact);

    final PuckController controller =
        container.read(puckControllerProvider.notifier)
          // Spanish on purpose: the SOS sheet is the surface where an
          // untranslated English word is least acceptable.
          ..setLocale(const Locale('es'));

    controller.handleGesture(PuckGestureKind.longPress);
    await tester.pump(); // the hold registers and the sheet appears
    return controller;
  }

  testWidgets('a fix that never lands still sends the message, late',
      (WidgetTester tester) async {
    // The regression this file exists for. The old code opened the composer
    // only when the body existed, the body only existed when the GPS came
    // back, and the countdown was shorter than the GPS timeout -- so a cold
    // fix produced no message, no retry and no error. Ever.
    final _FakeSms sms = _FakeSms();
    final _BlockedFix gps = _BlockedFix();
    final PuckController controller =
        await armed(tester, sms: sms, location: gps);

    expect(controller.sos, isNotNull);
    expect(controller.sos!.hasContact, isTrue);
    expect(controller.sos!.phase, SosPhase.counting);

    // The countdown runs out with the fix still pending.
    await tester.pump(PuckConstants.sosCountdown);
    expect(controller.sos!.phase, SosPhase.active);
    expect(controller.sos!.bodyPending, isTrue,
        reason: 'the send is owed, and remembered');
    expect(sms.bodies, isEmpty,
        reason: 'nothing is sent behind the user\'s back; it is owed');

    // Now the fix lands -- with no position, because the plugin is absent in a
    // test and because "no permission" is the same shape of failure.
    gps.release.complete();
    await tester.pump();

    expect(sms.bodies, hasLength(1), reason: 'the owed send is delivered');
    expect(sms.recipients.single, '+15550100');
    expect(sms.bodies.single, startsWith(es.sosMessage));
    expect(sms.bodies.single, contains(es.sosMessageNoLocation));
    expect(controller.sos!.bodyPending, isFalse);
    expect(controller.sos!.status, es.sosMessageReady);
  });

  testWidgets('with no contact, the sheet offers the dialer and sends nothing',
      (WidgetTester tester) async {
    final _FakeSms sms = _FakeSms();
    final PuckController controller = await armed(
      tester,
      sms: sms,
      location: _NoFix(),
      contact: '',
    );

    expect(controller.sos!.hasContact, isFalse);
    expect(controller.sos!.status, es.sosGettingLocation);

    await tester.pump(PuckConstants.sosCountdown);
    expect(controller.sos!.phase, SosPhase.active);
    expect(controller.sos!.status, es.sosNoContact);
    expect(sms.bodies, isEmpty);

    // Nothing on this device answers a `tel:` intent, so the sheet says so
    // rather than leaving a button that looks like it works.
    final bool opened = await controller.dialEmergency();
    expect(opened, isFalse);
    expect(controller.sos!.status, es.sosNoDialer);
    expect(controller.sos!.torchOn, isTrue);
  });

  testWidgets('a late fix does not replace the no-contact status',
      (WidgetTester tester) async {
    // "Location found" is true and useless when there is nobody to text. The
    // line has to keep pointing at the only action that works.
    final _FakeSms sms = _FakeSms();
    final _BlockedFix gps = _BlockedFix();
    final PuckController controller = await armed(
      tester,
      sms: sms,
      location: gps,
      contact: '',
    );

    await tester.pump(PuckConstants.sosCountdown);
    expect(controller.sos!.status, es.sosNoContact);

    gps.release.complete();
    await tester.pump();

    expect(controller.sos!.status, es.sosNoContact);
    expect(sms.bodies, isEmpty);
  });

  testWidgets('with no SMS app, the sheet says the handoff failed',
      (WidgetTester tester) async {
    final _FakeSms sms = _FakeSms(canOpen: false);
    final PuckController controller =
        await armed(tester, sms: sms, location: _NoFix());

    await tester.pump(PuckConstants.sosCountdown);

    expect(sms.bodies, hasLength(1), reason: 'the attempt is still made');
    expect(controller.sos!.smsHandoffFailed, isTrue);
    expect(controller.sos!.status, es.sosNoMessagingApp);
  });

  testWidgets('lift the finger and nothing is sent, ever',
      (WidgetTester tester) async {
    final _FakeSms sms = _FakeSms();
    final PuckController controller =
        await armed(tester, sms: sms, location: _NoFix());

    await tester.pump(const Duration(seconds: 1));
    expect(
      controller.sos!.secondsLeft,
      lessThan(PuckConstants.sosCountdown.inSeconds),
    );

    await controller.cancelSos();
    expect(controller.sos, isNull);

    // And nothing fires afterwards: the countdown timer is gone.
    await tester.pump(const Duration(seconds: 5));
    expect(sms.bodies, isEmpty);
  });

  testWidgets('the emergency number is whatever fits, and nothing else',
      (WidgetTester tester) async {
    expect(EmergencyNumbers.resolve(const Locale('en', 'US')).number, '911');
    expect(EmergencyNumbers.resolve(const Locale('en', 'GB')).number, '999');
    expect(EmergencyNumbers.resolve(const Locale('es', 'ES')).number, '112');
    expect(EmergencyNumbers.resolve(const Locale('es', 'MX')).number, '911');
    expect(EmergencyNumbers.resolve(const Locale('es', 'AR')).number, '911');
    expect(EmergencyNumbers.resolve(const Locale('en', 'IN')).number, '112');

    // A region nobody listed, and a device that did not say: the GSM fallback,
    // flagged as not-regional so the sheet can say so instead of implying
    // certainty it does not have.
    final EmergencyNumber unknown =
        EmergencyNumbers.resolve(const Locale('es', 'AQ'));
    expect(unknown.number, EmergencyNumbers.fallback);
    expect(unknown.isRegional, isFalse);

    final EmergencyNumber noRegion = EmergencyNumbers.resolve(null);
    expect(noRegion.number, EmergencyNumbers.fallback);
    expect(noRegion.isRegional, isFalse);
  });

  test('the dialer never opens for an empty or junk number', () async {
    // The one thing that must never happen in this class of code is a call.
    // `dialEmergency` opens `tel:` and stops there; with nothing to dial it
    // reports failure without touching the platform at all.
    final MessagingService service = MessagingService();
    expect(await service.dialEmergency(''), isFalse);
    expect(await service.dialEmergency('   '), isFalse);
    expect(await service.dialEmergency('abc'), isFalse);
  });
}
