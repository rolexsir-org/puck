import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/llm/groq_provider.dart';
import 'package:puck/src/data/repositories/settings_repository.dart';
import 'package:puck/src/providers.dart';

/// The only screen in Puck that is not the bubble.
///
/// Deliberately kept to four decisions: who gets the SOS, which key pays for
/// the thinking, and whether the phone should shake and shine.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _key;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final SettingsRepository s = ref.read(settingsProvider);
    _name = TextEditingController(text: s.contactName);
    _phone = TextEditingController(text: s.contactPhone);
    _key = TextEditingController(text: s.groqApiKey ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsRepository settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: PuckPalette.textMid,
                      splashRadius: 20,
                    ),
                    const Text('SETTINGS', style: PuckType.label),
                  ],
                ),
              ),
            ),

            // -- Emergency --------------------------------------------------
            _Section(
              title: 'EMERGENCY',
              children: <Widget>[
                _Field(
                  controller: _name,
                  label: 'Contact name',
                  hint: 'Mum',
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (String v) =>
                      unawaited(settings.setEmergencyContact(name: v)),
                ),
                _Field(
                  controller: _phone,
                  label: 'Contact number',
                  hint: '+91 98…',
                  keyboardType: TextInputType.phone,
                  onSubmitted: (String v) =>
                      unawaited(settings.setEmergencyContact(phone: v)),
                ),
                const _Note(
                  'Hold the bubble for three seconds to arm SOS. Puck opens your '
                  'SMS app with your location pre-filled — it never sends '
                  'anything itself, so an accidental hold stays recoverable.',
                ),
              ],
            ),

            // -- Intelligence -----------------------------------------------
            _Section(
              title: 'INTELLIGENCE',
              children: <Widget>[
                _Field(
                  controller: _key,
                  label: 'Groq API key',
                  hint: 'gsk_…',
                  obscure: _obscureKey,
                  onSubmitted: (String v) => unawaited(settings.setGroqApiKey(v)),
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscureKey = !_obscureKey),
                    child: Text(
                      _obscureKey ? 'SHOW' : 'HIDE',
                      style: PuckType.label,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _ModelChoice(
                  current: settings.llmModel,
                  onChanged: (String model) =>
                      unawaited(settings.setLlmModel(model)),
                ),
                const _Note(
                  'Stored in the iOS Keychain / Android Keystore, never in '
                  'backups. Get a free key at console.groq.com/keys. Without '
                  'one, Puck still answers coin flips, dice, sums, and the time.',
                ),
              ],
            ),

            // -- Behaviour ---------------------------------------------------
            _Section(
              title: 'BEHAVIOUR',
              children: <Widget>[
                _Switch(
                  label: 'Haptics',
                  value: settings.hapticsEnabled,
                  onChanged: settings.setHaptics,
                ),
                _Switch(
                  label: 'Flashlight on SOS',
                  value: settings.torchEnabled,
                  onChanged: settings.setTorch,
                ),
                _Switch(
                  label: 'SOS strobe (Morse)',
                  value: settings.strobeEnabled,
                  onChanged: settings.setStrobe,
                ),
                _Switch(
                  label: 'Jokes from the model',
                  value: settings.giggleFromModel,
                  onChanged: settings.setGiggleFromModel,
                ),
                const _Note(
                  'Jokes from the model costs one round-trip per double-tap and '
                  'needs a key. Off, Puck serves the bundled shuffle bag: '
                  'instant, offline, and it never repeats itself.',
                ),
                const _Note(
                  'Puck asks for permissions only when a gesture needs them: '
                  'calendar on first tap, location on first SOS or weather '
                  'check, microphone when you press the mic.',
                ),
              ],
            ),

            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Text('PUCK · v1.0.0', style: PuckType.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: PuckType.label),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onSubmitted,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: PuckPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PuckPalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  style: PuckType.body,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  textCapitalization: textCapitalization,
                  cursorWidth: 1.5,
                  onSubmitted: onSubmitted,
                  onEditingComplete: () => onSubmitted(controller.text),
                  decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: suffix,
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 40, minHeight: 24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: PuckType.body)),
          Switch.adaptive(
            value: value,
            onChanged: (bool v) => unawaited(onChanged(v)),
            activeThumbColor: PuckPalette.background,
            activeTrackColor: PuckPalette.textHigh,
            inactiveThumbColor: PuckPalette.textMid,
            inactiveTrackColor: PuckPalette.surfaceHi,
          ),
        ],
      ),
    );
  }
}

class _ModelChoice extends StatelessWidget {
  const _ModelChoice({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool fast = current == GroqLlmProvider.defaultModel;
    return Row(
      children: <Widget>[
        _Chip(
          label: 'gpt-oss-20b',
          caption: 'fastest',
          selected: fast,
          onTap: () => onChanged(GroqLlmProvider.defaultModel),
        ),
        const SizedBox(width: 10),
        _Chip(
          label: 'gpt-oss-120b',
          caption: 'smarter',
          selected: !fast,
          onTap: () => onChanged(GroqLlmProvider.fallbackModel),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? PuckPalette.textHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? PuckPalette.textHigh : PuckPalette.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: PuckType.detail.copyWith(
                color: selected ? PuckPalette.background : PuckPalette.textHigh,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              caption.toUpperCase(),
              style: PuckType.label.copyWith(
                fontSize: 8,
                color: selected
                    ? PuckPalette.background.withValues(alpha: 0.6)
                    : PuckPalette.textLow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
      child: Text(
        text,
        style: PuckType.detail.copyWith(fontSize: 12, height: 1.5),
      ),
    );
  }
}
