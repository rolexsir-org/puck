import 'dart:async';
import 'dart:collection';

import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/models/context.dart';

/// Reads the next thing on the user's calendar.
///
/// Permission is requested lazily, on the first tap that needs it -- Puck
/// launches into a black screen and asks for nothing.
///
/// The winning event is cached for [PuckConstants.snapshotCacheTtl]: calendar
/// state changes on the scale of minutes, not seconds, and the single tap
/// must never wait on a plugin round-trip twice in a row.
class CalendarService {
  CalendarService({dc.DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? dc.DeviceCalendarPlugin();

  final dc.DeviceCalendarPlugin _plugin;

  bool? _permissionGranted;

  CalendarEvent? _cache;
  DateTime _cacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> _ensurePermission() async {
    if (_permissionGranted != null) return _permissionGranted!;
    try {
      dc.Result<bool> status = await _plugin.hasPermissions();
      if (!status.isSuccess || status.data == null || !status.data!) {
        status = await _plugin.requestPermissions();
      }
      _permissionGranted = (status.data ?? false);
    } catch (_) {
      _permissionGranted = false;
    }
    return _permissionGranted!;
  }

  /// The soonest event that has not finished yet, or null.
  ///
  /// All calendars are searched, not just the default one -- people keep work
  /// and life in separate calendars, and "next meeting" doesn't care which.
  Future<CalendarEvent?> nextEvent({
    Duration lookahead = const Duration(hours: 16),
  }) async {
    final DateTime now = DateTime.now();
    final CalendarEvent? cached = _cache;
    final bool cacheLive = cached != null &&
        now.difference(_cacheAt) < PuckConstants.snapshotCacheTtl &&
        (cached.end == null || cached.end!.isAfter(now)) &&
        cached.start.isBefore(now.add(lookahead));
    if (cacheLive) {
      return cached;
    }

    if (!await _ensurePermission()) return null;

    try {
      final dc.Result<UnmodifiableListView<dc.Calendar>> calendars =
          await _plugin.retrieveCalendars();
      if (!calendars.isSuccess) return _cached(null, now);

      DateTime? bestStart;
      CalendarEvent? best;

      for (final dc.Calendar cal in calendars.data ?? <dc.Calendar>[]) {
        final String? id = cal.id;
        if (id == null || id.isEmpty) continue;

        final dc.Result<UnmodifiableListView<dc.Event>> res =
            await _plugin.retrieveEvents(
          id,
          dc.RetrieveEventsParams(
            startDate: now.subtract(const Duration(minutes: 15)),
            endDate: now.add(lookahead),
          ),
        );

        for (final dc.Event e in res.data ?? <dc.Event>[]) {
          if (_isSkippable(e)) continue;

          final DateTime? start = e.start;
          final DateTime? end = e.end;
          if (start == null) continue;
          // Skip anything already over.
          if (end != null && end.isBefore(now)) continue;
          // Way out in the future is not "next up".
          if (start.isAfter(now.add(lookahead))) continue;

          if (bestStart == null || start.isBefore(bestStart)) {
            bestStart = start;
            final String title = (e.title ?? '').trim();
            best = CalendarEvent(
              title: title.isEmpty ? 'Busy' : title,
              start: start,
              end: end,
              location: e.location,
              allDay: e.allDay ?? false,
            );
          }
        }
      }

      return _cached(best, now);
    } catch (_) {
      return _cache;
    }
  }

  CalendarEvent? _cached(CalendarEvent? value, DateTime at) {
    _cache = value;
    _cacheAt = at;
    return value;
  }

  /// Cancelled events and transparent ("free") entries are not commitments.
  bool _isSkippable(dc.Event e) {
    final dc.EventStatus? status = e.status;
    if (status != null && status == dc.EventStatus.Canceled) return true;
    return false;
  }
}
