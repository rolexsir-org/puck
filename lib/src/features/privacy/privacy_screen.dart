import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/services/feedback_service.dart';
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/l10n/puck_strings.dart';
import 'package:puck/src/providers.dart';

/// "What leaves your phone", in plain language, and the controls to stop it.
///
/// The two belong on one screen. A disclosure you cannot act on is a legal
/// artefact; a control with nothing to read is a switch nobody trusts.
///
/// Everything here is deliberately boring: a list of sentences, two buttons
/// and three lines of diagnostics. It is the only screen in Puck that is
/// allowed to be a list.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  String _version = '…';
  String _platform = '…';
  bool _speechAvailable = false;
  bool _confirmingErase = false;
  String? _flash;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDiagnostics());
  }

  Future<void> _loadDiagnostics() async {
    // Read from the framework global rather than `Theme.of(context)`: this
    // runs across an await, and touching a BuildContext after one is exactly
    // the bug the `use_build_context_synchronously` lint exists for.
    final String platform = defaultTargetPlatform.name;
    String version = '?';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // A platform that cannot report its own version is not a reason to show
      // an error; the line says "?" and everything else still works.
    }
    final bool speech = ref.read(speechServiceProvider).isAvailable;
    if (!mounted) return;
    setState(() {
      _version = version;
      _platform = platform;
      _speechAvailable = speech;
    });
  }

  /// A short, human-readable block for a bug report: version, platform, and
  /// whether the cloud path is on. No identifiers, no device names, no
  /// location -- the diagnostics are useful precisely because they contain
  /// nothing that would need to be scrubbed.
  String diagnosticsBlock(PuckStrings s) {
    final bool cloud = ref.read(settingsProvider).cloudEnabled;
    final String cloudWord =
        cloud ? s.diagnosticsCloudOn : s.diagnosticsCloudOff;
    final String speechWord = _speechAvailable
        ? s.diagnosticsAvailable
        : s.diagnosticsUnavailable;
    return <String>[
      '${s.diagnosticsVersion}: $_version',
      '${s.diagnosticsPlatform}: $_platform',
      '${s.diagnosticsCloud}: $cloudWord',
      '${s.diagnosticsSpeech}: $speechWord',
    ].join('\n');
  }

  Future<void> _sendFeedback() async {
    final PuckStrings s = PuckStrings.of(context);
    final bool opened = await FeedbackService.openMail(
      subject: 'Puck feedback',
      body: '\n\n---\n${diagnosticsBlock(s)}\n',
    );
    if (!mounted) return;
    setState(() => _flash = opened ? null : s.feedbackNoMail);
  }

  Future<void> _erase() async {
    final String done = PuckStrings.of(context).clearDataDone;
    await ref.read(settingsProvider).clearAllLocalData();
    if (!mounted) return;
    setState(() {
      _confirmingErase = false;
      _flash = done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final PuckStrings s = PuckStrings.of(context);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: <Widget>[
                  _BackRow(
                    label: s.back,
                    title: s.privacyScreenTitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 24),
                  Text(s.privacyIntro, style: PuckType.body),
                  const SizedBox(height: 24),
                  _Heading(text: s.privacySendsTitle),
                  _Bullet(text: s.privacyQuestion),
                  _Bullet(text: s.privacyEventTitle),
                  _Bullet(text: s.privacyEventWhen),
                  _Bullet(text: s.privacyEventWhere),
                  _Bullet(text: s.privacyBattery),
                  _Bullet(text: s.privacyWeather),
                  _Bullet(text: s.privacyTime),
                  _Bullet(text: s.privacyDeviceId),
                  const SizedBox(height: 20),
                  _Heading(text: s.privacyNeverTitle),
                  _Bullet(text: s.privacyNeverBody),
                  const SizedBox(height: 20),
                  _Bullet(text: s.privacyAttribution),
                  const Divider(height: 48, color: PuckPalette.divider),
                  _SwitchRow(
                    title: s.cloudTitle,
                    subtitle: s.cloudNote,
                    value: settings.cloudEnabled,
                    onChanged: (bool v) =>
                        unawaited(settings.setCloudEnabled(v)),
                  ),
                  const SizedBox(height: 24),
                  _Heading(text: s.diagnosticsTitle),
                  const SizedBox(height: 8),
                  Text(
                    diagnosticsBlock(s),
                    style: PuckType.body,
                  ),
                  const SizedBox(height: 24),
                  if (_confirmingErase)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(s.clearDataConfirm, style: PuckType.body),
                        const SizedBox(height: 8),
                        _RowButton(
                          label: s.clearDataAction,
                          destructive: true,
                          onTap: () => unawaited(_erase()),
                        ),
                        _RowButton(
                          label: s.clearDataCancel,
                          onTap: () =>
                              setState(() => _confirmingErase = false),
                        ),
                      ],
                    )
                  else
                    _RowButton(
                      label: s.clearDataTitle,
                      onTap: () => setState(() => _confirmingErase = true),
                    ),
                  const SizedBox(height: 8),
                  Text(s.feedbackNote, style: PuckType.label),
                  const SizedBox(height: 8),
                  _RowButton(
                    label: s.feedbackAction,
                    onTap: () => unawaited(_sendFeedback()),
                  ),
                  if (_flash != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(_flash!, style: PuckType.body),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({
    required this.label,
    required this.title,
    required this.onBack,
  });

  final String label;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Semantics(
            button: true,
            label: label,
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.chevron_left_rounded,
                      size: 24,
                      color: PuckPalette.textSec,
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: PuckType.fontFamily,
                        fontSize: 17,
                        color: PuckPalette.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: PuckType.primary),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(text, style: PuckType.primary),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: PuckPalette.textSec,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Flexible(child: Text(text, style: PuckType.body)),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: PuckType.primary),
                const SizedBox(height: 6),
                Text(subtitle, style: PuckType.label),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MergeSemantics(
            child: SizedBox(
              height: 48,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: PuckPalette.textPrim,
                activeTrackColor: PuckPalette.textSec,
                inactiveThumbColor: PuckPalette.textMuted,
                inactiveTrackColor: PuckPalette.mutedBg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: PuckConstants.screenMargin / 2,
              ),
              decoration: BoxDecoration(
                color: destructive ? PuckPalette.emergency : PuckPalette.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: PuckType.primary.copyWith(
                  // Black on the emergency fill: white on it fails AA at this
                  // size (see PuckPalette).
                  color: destructive ? PuckPalette.background : null,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
