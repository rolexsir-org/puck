import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/providers.dart';

/// The one screen that is not the bubble.
///
/// Two decisions live here: who the SOS message goes to, and the key that
/// pays for the answers. Everything else in Puck has a correct default and
/// deliberately no UI.
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

  @override
  void initState() {
    super.initState();
    final SettingsRepository s = ref.read(settingsProvider);
    _contact = TextEditingController(text: s.contactPhone);
    _key = TextEditingController(text: s.groqApiKey ?? '');

    // Saved on leave, not on a button. A settings screen that makes you
    // press "save" is a form; this is a place you visit once.
    _contactFocus.addListener(_saveContactOnBlur);
    _keyFocus.addListener(_saveKeyOnBlur);
  }

  void _saveContactOnBlur() {
    if (_contactFocus.hasFocus) return;
    unawaited(ref.read(settingsProvider).setContactPhone(_contact.text));
  }

  void _saveKeyOnBlur() {
    if (_keyFocus.hasFocus) return;
    unawaited(ref.read(settingsProvider).setGroqApiKey(_key.text));
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

  @override
  Widget build(BuildContext context) {
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
                  // "< Back  Settings" -- the back row is a 44pt tap target.
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: <Widget>[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 24,
                                color: PuckPalette.textSec,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'Back',
                                style: TextStyle(
                                  fontFamily: PuckType.fontFamily,
                                  fontSize: 17,
                                  color: PuckPalette.textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Settings', style: PuckType.primary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Text('API key', style: PuckType.primary),
                  const SizedBox(height: 10),
                  _Input(
                    controller: _key,
                    focusNode: _keyFocus,
                    hint: 'Paste',
                    keyboardType: TextInputType.url,
                    suffix: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_pasteKey()),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text('Paste', style: PuckType.body),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Free at console.groq.com/keys',
                    style: PuckType.label,
                  ),
                  const SizedBox(height: 32),

                  const Text('Emergency contact', style: PuckType.primary),
                  const SizedBox(height: 10),
                  _Input(
                    controller: _contact,
                    focusNode: _contactFocus,
                    hint: 'Number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The SOS message opens in Messages, ready to send. '
                    'Nothing is ever sent on its own.',
                    style: PuckType.label,
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(height: 1, color: PuckPalette.divider),
                  ),

                  Text(
                    'Puck cancels itself when you release early. '
                    'It has done that $cancels '
                    '${cancels == 1 ? 'time' : 'times'}.',
                    style: PuckType.body,
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(height: 1, color: PuckPalette.divider),
                  ),
                ],
              ),
            ),
            // The quietest line on the screen. Centred, 32px up.
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                'Version 1.0 · Made for hackathon',
                textAlign: TextAlign.center,
                style: PuckType.label.copyWith(color: PuckPalette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 56px tall, #111111, 16px corners. No borders, no labels inside.
class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final Widget? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: PuckPalette.card,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
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
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      ),
    );
  }
}
