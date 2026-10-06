import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/l10n/puck_strings.dart';
import 'package:puck/src/providers.dart';

/// The one screen that is not the bubble.
///
/// Order is deliberate, top to bottom: what leaves the phone (and the switch
/// that stops it), then the emergency contact, then how long the hold takes,
/// then the optional key. The first thing on the screen is the thing a
/// cautious person came looking for, and the advanced corner is last.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _contact;
  late final TextEditingController _key;
  final FocusNode _contactFocus = FocusNode();
  final FocusNode _keyFocus = FocusNode();

  String _version = '…';
  bool _confirmingErase = false;
  String? _flash;

  @override
  void initState() {
    super.initState();
    final SettingsRepository settings = ref.read(settingsProvider);
    _contact = TextEditingController(text: settings.contactPhone);
    _key = TextEditingController(text: settings.groqApiKey ?? '');

    // Saved on leave, not on a button. A settings screen that makes you press
    // "save" is a form; this is a place you visit once. It is also why the
    // key is not written to the Keystore on every keystroke.
    _contactFocus.addListener(_saveContactOnBlur);
    _keyFocus.addListener(_saveKeyOnBlur);
    unawaited(_loadVersion());
  }

  void _saveContactOnBlur() {
    if (_contactFocus.hasFocus) return;
    unawaited(ref.read(settingsProvider).setContactPhone(_contact.text));
  }

  void _saveKeyOnBlur() {
    if (_keyFocus.hasFocus) return;
    unawaited(ref.read(settingsProvider).setGroqApiKey(_key.text));
  }

  Future<void> _loadVersion() async {
    String version = '?';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // A device that cannot report its own version still gets a settings
      // screen; the line says "?" rather than the screen failing.
    }
    if (!mounted) return;
    setState(() => _version = version);
  }

  @override
  void dispose() {
    _contactFocus.removeListener(_saveContactOnBlur);
    _keyFocus.removeListener(_saveKeyOnBlur);
    _contact.dispose();
    _key.dispose();
    _contactFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _pasteKey() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _key.text = text;
    _key.selection = TextSelection.collapsed(offset: text.length);
    await ref.read(settingsProvider).setGroqApiKey(text);
  }

  Future<void> _erase() async {
    final String done = PuckStrings.of(context).clearDataDone;
    await ref.read(settingsProvider).clearAllLocalData();
    if (!mounted) return;
    setState(() {
      _confirmingErase = false;
      _flash = done;
      _contact.clear();
      _key.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final PuckStrings s = PuckStrings.of(context);
    final SettingsRepository settings = ref.watch(settingsProvider);
    final int cancels = settings.releaseCancels;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                children: <Widget>[
                  _BackRow(
                    label: s.back,
                    title: s.settingsTitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 28),

                  // -- What leaves the phone, first -------------------------
                  _SwitchRow(
                    title: s.cloudTitle,
                    subtitle: s.cloudNote,
                    value: settings.cloudEnabled,
                    onChanged: (bool v) =>
                        unawaited(settings.setCloudEnabled(v)),
                  ),
                  const SizedBox(height: 12),
                  _RowButton(
                    label: s.privacyTitle,
                    subtitle: s.privacyNote,
                    onTap: () => Navigator.of(context).pushNamed('/privacy'),
                  ),
                  const SizedBox(height: 12),
                  if (_confirmingErase) ...<Widget>[
                    Text(s.clearDataConfirm, style: PuckType.body),
                    const SizedBox(height: 8),
                    _RowButton(
                      label: s.clearDataAction,
                      destructive: true,
                      onTap: () => unawaited(_erase()),
                    ),
                    _RowButton(
                      label: s.clearDataCancel,
                      onTap: () => setState(() => _confirmingErase = false),
                    ),
                  ] else
                    _RowButton(
                      label: s.clearDataTitle,
                      onTap: () => setState(() => _confirmingErase = true),
                    ),
                  if (_flash != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(_flash!, style: PuckType.body),
                    ),
                  ],

                  const _SectionDivider(),

                  // -- Emergency contact ------------------------------------
                  _Heading(text: s.emergencyContactTitle),
                  const SizedBox(height: 10),
                  _Input(
                    controller: _contact,
                    focusNode: _contactFocus,
                    label: s.emergencyContactTitle,
                    hint: s.emergencyContactHint,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  Text(s.emergencyContactNote, style: PuckType.label),

                  const _SectionDivider(),

                  // -- Hold length ------------------------------------------
                  _Heading(text: s.holdTitle),
                  const SizedBox(height: 10),
                  _HoldChoices(
                    value: settings.sosHoldSeconds,
                    strings: s,
                    onChanged: (int seconds) =>
                        unawaited(settings.setSosHoldSeconds(seconds)),
                  ),
                  const SizedBox(height: 8),
                  Text(s.holdNote, style: PuckType.label),

                  const _SectionDivider(),

                  // -- Advanced ---------------------------------------------
                  _Heading(text: s.advancedTitle),
                  const SizedBox(height: 6),
                  Text(s.advancedNote, style: PuckType.label),
                  const SizedBox(height: 18),
                  Text(s.apiKeyTitle, style: PuckType.primary),
                  const SizedBox(height: 10),
                  _Input(
                    controller: _key,
                    focusNode: _keyFocus,
                    label: s.apiKeyTitle,
                    hint: s.apiKeyHint,
                    keyboardType: TextInputType.url,
                    suffix: Semantics(
                      button: true,
                      label: s.paste,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(_pasteKey()),
                          child: SizedBox(
                            height: 48,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(s.paste, style: PuckType.body),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.apiKeyNote, style: PuckType.label),

                  const _SectionDivider(),

                  Text(s.releaseCancels(cancels), style: PuckType.body),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                '${s.diagnosticsVersion} $_version',
                textAlign: TextAlign.center,
                style: PuckType.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "< Back  Settings" -- a 48dp row, with a real button semantics node.
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
                    const SizedBox(width: 2),
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

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Divider(height: 1, color: PuckPalette.divider),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: PuckType.primary),
    );
  }
}

/// The hold length, as three real buttons.
///
/// This is the only setting that exists purely to lower a physical demand.
/// The default stays 3s -- the design constant is not negotiable -- but a
/// person with a tremor can take the demand down to one second without
/// touching the constant the pocket-safety argument depends on.
class _HoldChoices extends StatelessWidget {
  const _HoldChoices({
    required this.value,
    required this.strings,
    required this.onChanged,
  });

  final int value;
  final PuckStrings strings;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final Map<int, String> choices = <int, String>{
      1: strings.holdOneSecond,
      2: strings.holdTwoSeconds,
      3: strings.holdThreeSeconds,
    };

    return Row(
      children: <Widget>[
        for (final MapEntry<int, String> choice in choices.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: choice.key == value,
                label: choice.value,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(choice.key),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: choice.key == value
                            ? PuckPalette.mutedBg
                            : PuckPalette.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: choice.key == value
                              ? PuckPalette.textSec
                              : PuckPalette.card,
                        ),
                      ),
                      child: Text(choice.value, style: PuckType.body),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
    this.subtitle,
    this.destructive = false,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: label,
        hint: subtitle,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
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

/// 56px tall, #111111, 16px corners. No borders, no labels inside -- the
/// heading above it is the label, and it is also the semantics label, because
/// a bare text field is announced as "edit box" and nothing else.
class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final Widget? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: PuckPalette.card,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Semantics(
          textField: true,
          label: label,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            autocorrect: false,
            enableSuggestions: false,
            style: PuckType.primary.copyWith(fontWeight: FontWeight.w400),
            cursorWidth: 2,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              suffixIcon: suffix,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ),
      ),
    );
  }
}
