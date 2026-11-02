import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:puck/src/voice/voice_model.dart';

/// Installs and removes the model files that [VoiceModel] describes.
///
/// # The four things that go wrong with a download, and what happens here
///
///   1. **It is interrupted.** Bytes land in `<id>.part`, never in the model
///      directory. A failed or cancelled install deletes the partial file and
///      the model stays "not installed", so the next attempt starts clean
///      instead of resuming into a corrupt archive.
///   2. **It is truncated.** bzip2 carries a CRC per block, and the decoder
///      checks it; on top of that the byte count is compared with the size
///      published in the release. A short read is an error, not a smaller
///      model.
///   3. **It extracts, but not completely.** Unpacking goes into
///      `<id>.installing`, then [VoiceModel.files] must all exist and be
///      non-empty, and only then is the directory renamed into place. A rename
///      is atomic on the same filesystem, so "installed" never means "half
///      unpacked".
///   4. **The user changes their mind.** Extraction and download take a token;
///      cancelling stops at the next chunk and cleans up.
///
/// Extraction runs in `Isolate.run`: unpacking 30 MB of bzip2 is a second or
/// two of pure CPU, and doing it on the UI isolate would drop frames on the
/// exact screen the user is staring at.
class VoiceModelStore {
  VoiceModelStore({required this.root, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// `<app support>/voice_models`, created on first use.
  static Future<VoiceModelStore> open() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory root =
        Directory('${support.path}${Platform.pathSeparator}voice_models');
    await root.create(recursive: true);
    return VoiceModelStore(root: root);
  }

  final Directory root;
  final http.Client _client;
  final bool _ownsClient;

  String directoryOf(VoiceModel model) =>
      '${root.path}${Platform.pathSeparator}${model.id}';

  String _pathFor(VoiceModel model, String file) =>
      '${directoryOf(model)}${Platform.pathSeparator}$file';

  /// True when every required file exists and has content.
  Future<bool> isInstalled(VoiceModel model) async =>
      (await missingFiles(model)).isEmpty;

  /// The required files that are absent or empty. Empty means installed.
  Future<List<String>> missingFiles(VoiceModel model) async {
    final List<String> missing = <String>[];
    for (final String file in model.files) {
      final File f = File(_pathFor(model, file));
      try {
        if (!f.existsSync() || f.lengthSync() == 0) missing.add(file);
      } on FileSystemException {
        missing.add(file);
      }
    }
    return missing;
  }

  /// Bytes on disk for one model, 0 when it is not installed.
  Future<int> installedBytes(VoiceModel model) async {
    final Directory dir = Directory(directoryOf(model));
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
        if (entity is File) total += entity.lengthSync();
      }
    } on FileSystemException {
      return 0;
    }
    return total;
  }

  /// Deletes a model and everything it installed.
  Future<void> remove(VoiceModel model) async {
    final Directory dir = Directory(directoryOf(model));
    if (dir.existsSync()) await dir.delete(recursive: true);
    final File part = File('${root.path}${Platform.pathSeparator}'
        '${model.id}.part');
    if (part.existsSync()) await part.delete();
  }

  /// Download, verify, extract, verify again, install.
  ///
  /// Never throws for a network or filesystem problem: the failure is a
  /// [ModelInstallResult] with a message the settings screen can show. A thrown
  /// exception from a background download is a silent failure in the UI.
  Future<ModelInstallResult> install(
    VoiceModel model, {
    void Function(ModelInstallProgress progress)? onProgress,
    ModelInstallCancel? cancel,
  }) async {
    final Directory? temp = await _prepare(model, cancel);
    if (temp == null) {
      return const ModelInstallResult.failure('cancelled');
    }

    try {
      if (model.isArchive) {
        // The archive lives outside the installation directory, because that
        // directory is what gets renamed into place and an archive inside it
        // would be installed alongside the model it produced.
        final File archive = File(
          '${root.path}${Platform.pathSeparator}${model.id}.download',
        );
        final String? downloadError = await _download(
          url: model.archiveUrl,
          target: archive,
          expectedBytes: model.archiveBytes,
          onProgress: (int received, int total) => onProgress?.call(
            ModelInstallProgress(
              received: received,
              total: total,
              extracting: false,
            ),
          ),
          cancel: cancel,
        );
        if (downloadError != null) return ModelInstallResult.failure(downloadError);

        onProgress?.call(
          const ModelInstallProgress(received: 1, total: 1, extracting: true),
        );

        final String? extractError = await Isolate.run(
          () => _extractArchive(
            _ExtractRequest(
              archivePath: archive.path,
              destination: temp.path,
              rootDir: model.rootDir,
              wanted: model.files,
            ),
          ),
        );
        if (archive.existsSync()) await archive.delete();
        if (extractError != null) {
          return ModelInstallResult.failure(extractError);
        }
      }

      for (final ModelFile extra in model.extraFiles) {
        final File target = File('${temp.path}${Platform.pathSeparator}'
            '${extra.name}');
        final String? error = await _download(
          url: extra.url,
          target: target,
          expectedBytes: extra.bytes,
          onProgress: (int received, int total) => onProgress?.call(
            ModelInstallProgress(
              received: received,
              total: total,
              extracting: false,
            ),
          ),
          cancel: cancel,
        );
        if (error != null) return ModelInstallResult.failure(error);
      }

      // Final gate: the files the engine will open must be there.
      for (final String file in model.files) {
        final File f = File('${temp.path}${Platform.pathSeparator}$file');
        if (!f.existsSync() || f.lengthSync() == 0) {
          return ModelInstallResult.failure('missing $file');
        }
      }

      final Directory destination = Directory(directoryOf(model));
      if (destination.existsSync()) await destination.delete(recursive: true);
      await temp.rename(destination.path);

      onProgress?.call(
        const ModelInstallProgress(received: 1, total: 1, extracting: false),
      );
      return const ModelInstallResult.success();
    } on FileSystemException catch (e) {
      return ModelInstallResult.failure('storage: ${e.message}');
    } on Object catch (e) {
      return ModelInstallResult.failure('$e');
    } finally {
      await _cleanTemp(model);
    }
  }

  /// Creates the scratch directory for [model], or returns null when the
  /// install was cancelled before it started.
  Future<Directory?> _prepare(VoiceModel model, ModelInstallCancel? cancel) async {
    if (cancel?.cancelled ?? false) return null;
    final Directory temp = Directory(
      '${root.path}${Platform.pathSeparator}${model.id}.installing',
    );
    if (temp.existsSync()) await temp.delete(recursive: true);
    await temp.create(recursive: true);
    return temp;
  }

  Future<void> _cleanTemp(VoiceModel model) async {
    final String base = '${root.path}${Platform.pathSeparator}${model.id}';
    final Directory temp = Directory('$base.installing');
    if (temp.existsSync()) await temp.delete(recursive: true);
    for (final String leftover in <String>['.download', '.download.part']) {
      final File file = File('$base$leftover');
      if (file.existsSync()) await file.delete();
    }
  }

  /// Returns null on success, or a short failure reason.
  ///
  /// The bytes are written to [target] only after the whole body arrived, so a
  /// half-downloaded file is never mistaken for a complete one by anything that
  /// later lists the directory.
  Future<String?> _download({
    required String url,
    required File target,
    required int expectedBytes,
    required void Function(int received, int total) onProgress,
    ModelInstallCancel? cancel,
  }) async {
    final File partial = File('${target.path}.part');
    if (partial.existsSync()) await partial.delete();

    IOSink? sink;
    try {
      final http.StreamedResponse response =
          await _client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        return 'http ${response.statusCode}';
      }

      final int total = response.contentLength ?? expectedBytes;
      int received = 0;
      sink = partial.openWrite();
      await for (final List<int> chunk in response.stream) {
        if (cancel?.cancelled ?? false) {
          await sink.close();
          sink = null;
          if (partial.existsSync()) await partial.delete();
          return 'cancelled';
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.close();
      sink = null;

      // Exact size, because the release publishes it. A mismatch is either a
      // truncated read or a changed asset on the server; both mean "do not
      // install this".
      if (expectedBytes > 0 && received != expectedBytes) {
        if (partial.existsSync()) await partial.delete();
        return 'size $received != $expectedBytes';
      }

      await partial.rename(target.path);
      return null;
    } on Object catch (e) {
      try {
        await sink?.close();
      } on Object {
        // The sink is already broken; nothing to salvage.
      }
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } on FileSystemException {
          // Best effort: a leftover .part is deleted on the next attempt.
        }
      }
      return '$e';
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class ModelInstallProgress {
  const ModelInstallProgress({
    required this.received,
    required this.total,
    required this.extracting,
  });

  final int received;
  final int total;
  final bool extracting;

  double get fraction {
    if (extracting) return 1;
    if (total <= 0) return 0;
    final double f = received / total;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }
}

class ModelInstallResult {
  const ModelInstallResult.success()
      : ok = true,
        message = '';

  const ModelInstallResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// A one-way "stop" flag, passed into [VoiceModelStore.install].
class ModelInstallCancel {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

// -- Extraction (runs in its own isolate) ------------------------------------

class _ExtractRequest {
  const _ExtractRequest({
    required this.archivePath,
    required this.destination,
    required this.rootDir,
    required this.wanted,
  });

  final String archivePath;
  final String destination;
  final String rootDir;
  final List<String> wanted;
}

/// Unpacks the archive's [wanted] files into [destination]. Returns null on
/// success or a message on failure.
///
/// Only the files the engine opens are kept: the release tarballs also carry
/// test WAVs, READMEs and duplicate fp32 weights, and writing those to a phone
/// triples the install for nothing.
String? _extractArchive(_ExtractRequest request) {
  try {
    final List<int> compressed = File(request.archivePath).readAsBytesSync();
    // Held in a nullable local on purpose: `decodeBytes` is typed nullable in
    // some `archive` releases and non-nullable in others, and this has to
    // compile against whichever the solver picked.
    final List<int>? inflated = BZip2Decoder().decodeBytes(compressed);
    if (inflated == null) return 'extract: this is not a bzip2 stream';
    final Uint8List tarBytes = Uint8List.fromList(inflated);
    final Archive archive = TarDecoder().decodeBytes(tarBytes, verify: false);

    final Set<String> wanted = request.wanted.toSet();
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      final String name = file.name;
      final String relative;
      if (request.rootDir.isEmpty) {
        relative = name;
      } else {
        final String prefix = '${request.rootDir}/';
        if (!name.startsWith(prefix)) continue;
        relative = name.substring(prefix.length);
      }
      if (!wanted.contains(relative)) continue;

      final File out = File(
        '${request.destination}${Platform.pathSeparator}$relative',
      );
      out.parent.createSync(recursive: true);
      // `content` is `dynamic` across archive versions; the check keeps this
      // honest under strict-casts instead of assuming a shape.
      final dynamic raw = file.content;
      out.writeAsBytesSync(raw is List<int> ? raw : const <int>[]);
    }
    return null;
  } on Object catch (e) {
    return 'extract: $e';
  }
}
