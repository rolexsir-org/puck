import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/l10n/puck_strings.dart';
import 'package:puck/src/providers.dart';
import 'package:puck/src/voice/model_store.dart';
import 'package:puck/src/voice/voice_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// The voice models, with their real sizes on the buttons.
///
/// # Why this screen exists at all
///
/// Because 30 MB is a decision, not a detail. The alternative designs are worse:
/// bundling it in the APK makes Puck a 40 MB app that nobody with a cheap phone
/// will install, and downloading it silently on first launch spends someone's
/// mobile data without asking. So the download is a row, on a screen, that says
/// what it costs and what it is for.
///
/// Nothing here downloads automatically -- every byte moves because somebody
/// pressed the row -- and a partial download is deleted rather than left to rot
/// in the app's support directory.
class VoiceModelsScreen extends ConsumerStatefulWidget {
  const VoiceModelsScreen({super.key});

  @override
  ConsumerState<VoiceModelsScreen> createState() => _VoiceModelsScreenState();
}

class _VoiceModelsScreenState extends ConsumerState<VoiceModelsScreen> {
  late final VoiceModelStore _store;

  final Map<String, bool> _installed = <String, bool>{};
  final Map<String, double> _progress = <String, double>{};
  final Map<String, String> _error = <String, String>{};
  final Map<String, ModelInstallCancel> _tokens =
      <String, ModelInstallCancel>{};
  final Map<String, int> _bytes = <String, int>{};

  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _store = ref.read(voiceModelStoreProvider);
    unawaited(_scan());
  }

  Future<void> _scan() async {
    for (final VoiceModel model in VoiceModels.catalogue) {
      final bool installed = await _store.isInstalled(model);
      final int bytes = installed ? await _store.installedBytes(model) : 0;
      if (!mounted) return;
      setState(() {
        _installed[model.id] = installed;
        _bytes[model.id] = bytes;
      });
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _install(VoiceModel model) async {
    final ModelInstallCancel token = ModelInstallCancel();
    setState(() {
      _tokens[model.id] = token;
      _progress[model.id] = 0;
      _error.remove(model.id);
    });

    final ModelInstallResult result = await _store.install(
      model,
      cancel: token,
      onProgress: (ModelInstallProgress progress) {
        if (!mounted || token.cancelled) return;
        setState(() => _progress[model.id] = progress.fraction);
      },
    );

    if (!mounted) return;
    setState(() {
      _tokens.remove(model.id);
      _progress.remove(model.id);
      if (!result.ok && result.message != 'cancelled') {
        _error[model.id] = result.message;
      }
    });
    await _scan();
  }

  Future<void> _delete(VoiceModel model) async {
    await _store.remove(model);
    await _scan();
  }

  Future<void> _cancel(VoiceModel model) async {
    _tokens[model.id]?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final PuckStrings s = PuckStrings.of(context);

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
                    title: s.voiceModelsTitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  Text(s.voiceModelsNote, style: PuckType.label),
                  const SizedBox(height: 8),
                  Text(s.voiceModelSizeNote, style: PuckType.label),
                  const SizedBox(height: 20),
                  if (_scanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (final VoiceModel model in VoiceModels.catalogue) ...
                        <Widget>[
                      _ModelCard(
                        model: model,
                        installed: _installed[model.id] ?? false,
                        installedBytes: _bytes[model.id] ?? 0,
                        progress: _progress[model.id],
                        error: _error[model.id],
                        required: VoiceModels.requiredForCommands
                            .contains(model),
                        strings: s,
                        onInstall: () => unawaited(_install(model)),
                        onCancel: () => unawaited(_cancel(model)),
                        onDelete: () => unawaited(_delete(model)),
                      ),
                      const SizedBox(height: 12),
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

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.installed,
    required this.installedBytes,
    required this.progress,
    required this.error,
    required this.required,
    required this.strings,
    required this.onInstall,
    required this.onCancel,
    required this.onDelete,
  });

  final VoiceModel model;
  final bool installed;
  final int installedBytes;

  /// Null when not downloading; 0-1 while it runs.
  final double? progress;
  final String? error;
  final bool required;
  final PuckStrings strings;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool downloading = progress != null;
    final String megabytes = '${model.totalMegabytes}';
    final String sizeLabel = installed
        ? strings.voiceModelBytes('${(installedBytes / 1000000).round()}')
        : strings.voiceModelBytes(megabytes);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PuckPalette.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(model.name, style: PuckType.primary),
              ),
              const SizedBox(width: 12),
              Text(
                installed ? strings.voiceModelInstalled : sizeLabel,
                style: PuckType.label.copyWith(
                  color: installed ? PuckPalette.success : PuckPalette.textSec,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            required
                ? '${strings.voiceModelRequired} · ${model.license}'
                : '${strings.voiceModelOptional} · ${model.license}',
            style: PuckType.label,
          ),
          if (model.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(model.note, style: PuckType.label),
          ],
          if (progress != null) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: PuckPalette.mutedBg,
              valueColor: const AlwaysStoppedAnimation<Color>(
                PuckPalette.textPrim,
              ),
            ),
            const SizedBox(height: 10),
            _TextButton(
              // "Cancel" during a download: the token stops at the next chunk
              // and the partial file is deleted.
              label: strings.sosCancel,
              onTap: onCancel,
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (!installed)
                  _TextButton(
                    label: strings.voiceModelDownload,
                    emphasised: true,
                    onTap: onInstall,
                  )
                else
                  _TextButton(
                    label: strings.voiceModelDelete,
                    onTap: onDelete,
                  ),
                const Spacer(),
                _TextButton(
                  label: strings.voiceModelLicense,
                  onTap: () => unawaited(
                    launchUrl(
                      Uri.parse(model.licenseUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              error!,
              style: PuckType.label.copyWith(color: PuckPalette.emergency),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable line of text, 48dp tall, with real button semantics.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onTap,
    this.emphasised = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: PuckType.body.copyWith(
                    color: emphasised
                        ? PuckPalette.textPrim
                        : PuckPalette.textSec,
                  ),
                ),
              ),
            ),
          ),
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
                    const SizedBox(width: 2),
                    Text(label, style: PuckType.body),
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
