import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/features/puck/puck_controller.dart';
import 'package:puck/src/providers.dart';

/// The SOS sheet.
///
/// Shown only after a deliberate three-second hold, and styled with the one
/// non-monochrome colour in the app. The accent is not decoration -- it is the
/// signal that this is the one surface where Puck is loud.
///
/// Sending is a two-step action by design. A pocket is a hostile input device
/// and an accidental emergency message has real costs, so the torch and the
/// vibrations start immediately (useful, harmless, attention-grabbing) while
/// the message itself waits behind a deliberate tap.
class SosSheet extends ConsumerStatefulWidget {
  const SosSheet({required this.controller, super.key});

  final PuckController controller;

  @override
  ConsumerState<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends ConsumerState<SosSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic));

  bool _closing = false;

  Future<void> _dismiss({required bool send}) async {
    if (_closing) return;
    _closing = true;
    if (send) {
      await widget.controller.sendSos();
      return;
    }
    await _slide.reverse();
    await widget.controller.cancelSos();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SosView? sos = widget.controller.sos;
    if (sos == null) return const SizedBox.shrink();

    final SettingsRepository settings = ref.watch(settingsProvider);
    final bool hasContact = settings.hasEmergencyContact;
    final bool locating = sos.phase == SosPhase.locating;

    return Stack(
      children: <Widget>[
        // Scrim. Tapping it does NOT dismiss -- SOS stays until you say why.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ColoredBox(
              color: PuckPalette.background.withValues(alpha: 0.72),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SlideTransition(
            position: _offset,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: PuckPalette.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: PuckPalette.danger.withValues(alpha: 0.55),
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 40,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: PuckPalette.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'SOS ARMED',
                          style: PuckType.label.copyWith(
                            color: PuckPalette.danger,
                          ),
                        ),
                        const Spacer(),
                        if (sos.torchOn)
                          Text(
                            'TORCH ON',
                            style: PuckType.label.copyWith(fontSize: 9),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      locating ? 'Locating…' : 'Ready to send',
                      style: PuckType.headline.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(sos.status, style: PuckType.detail),
                    const SizedBox(height: 18),
                    // Message preview -- the user should see exactly what goes
                    // out before it goes out.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PuckPalette.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PuckPalette.hairline),
                      ),
                      child: Text(
                        sos.body ?? 'Building message…',
                        style: PuckType.mono.copyWith(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      hasContact
                          ? 'TO  ${settings.contactLabel}  ·  ${_mask(settings.contactPhone)}'
                          : 'NO EMERGENCY CONTACT SET',
                      style: PuckType.label.copyWith(
                        color: hasContact ? PuckPalette.textMid : PuckPalette.danger,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SosButton(
                      label: hasContact
                          ? 'SEND SMS TO ${settings.contactLabel.toUpperCase()}'
                          : 'ADD AN EMERGENCY CONTACT',
                      filled: true,
                      enabled: !locating,
                      onTap: () {
                        if (!hasContact) {
                          Navigator.of(context).pushNamed('/settings');
                          return;
                        }
                        unawaited(_dismiss(send: true));
                      },
                    ),
                    const SizedBox(height: 10),
                    _SosButton(
                      label: "I'M SAFE — CANCEL",
                      filled: false,
                      enabled: true,
                      onTap: () => unawaited(_dismiss(send: false)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "+91 98••• ••210" -- enough to confirm the number, not enough to leak it
  /// into a screenshot.
  static String _mask(String phone) {
    final String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return phone;
    final String head = digits.substring(0, 2);
    final String tail = digits.substring(digits.length - 3);
    return '+$head•••••$tail';
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? PuckPalette.textHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: filled ? null : Border.all(color: PuckPalette.hairline),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PuckType.label.copyWith(
              fontSize: 11,
              color: filled ? PuckPalette.background : PuckPalette.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
