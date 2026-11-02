import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puck/src/voice/model_store.dart';
import 'package:puck/src/voice/voice_model.dart';

/// The model store, on a real temporary directory and a fake HTTP client.
///
/// A half-installed model is worse than no model: the engine opens a file that
/// is there and crashes, or opens a file that is truncated and transcribes
/// noise. These tests are the invariants that stop that happening, exercised
/// without a device, a network or a download.
///
/// What is *not* covered here: the real release assets. Sizes and URLs were
/// checked against the GitHub release API, but no byte has been downloaded by a
/// test in this checkout.

/// A real, tiny `.tar.bz2` (built with Python's `tarfile` + `bz2`), so the
/// extraction path is exercised against the same container format the releases
/// use rather than against a mock of it.
///
/// Contents: `model-x/encoder_model.ort`, `model-x/tokens.txt`,
/// `model-x/README.md`, `model-x/test_wavs/0.wav`, `other-dir/ignored.txt`.
const String _tarballBase64 =
    'QlpoOTFBWSZTWX79aFgAAQXfgMuYQAP/gD6rnCD+75/AaogwAPjbBqaibUzUyaNMQwmIAaNMj1D1D0hBFD1Hq'
    'GIAGAQZPU2pkZGAEkk9VP1T2pHtUG1M0TQaaD1NpAbUA2phf8sa+JDjIZatr8LgiFKEkV12ShejKiYh80XzY'
    '0byMSEhgRsgK7ZO2r3DUz/GJvsix0IdHJpggWmaICBXW23a4oFnJdkkQgWUO6hoqozoaAgR8USEZhAj7+2lrw'
    'rnb6l0CYklKbiS1uKQIJrA4gQOgpSQLAaPCgi3GD6vbLSgWM+BxBh5v9Xr+H/Au4WEQmCeMyE8KUSxtJR3UcC'
    'Mu0vFEyUtz1FhgiZvj16A5TpSA/xdyRThQkH79aFg';

Uint8List _tarball() => base64Decode(_tarballBase64);

/// The Silero shape: one file, no archive.
const VoiceModel _singleFileModel = VoiceModel(
  id: 'single-file',
  name: 'Single file',
  kind: VoiceModelKind.vad,
  license: 'MIT',
  licenseUrl: 'https://example.invalid/licence',
  extraFiles: <ModelFile>[
    ModelFile(
      name: 'silero_vad.onnx',
      url: 'https://example.invalid/silero_vad.onnx',
      bytes: 11,
    ),
  ],
  files: <String>['silero_vad.onnx'],
);

/// The archive shape: a tarball with a root directory and files to ignore.
const VoiceModel _archiveModel = VoiceModel(
  id: 'archive',
  name: 'Archive',
  kind: VoiceModelKind.asr,
  license: 'MIT',
  licenseUrl: 'https://example.invalid/licence',
  archiveUrl: 'https://example.invalid/model.tar.bz2',
  archiveBytes: 285,
  rootDir: 'model-x',
  files: <String>['encoder_model.ort', 'tokens.txt'],
);

void main() {
  late Directory root;
  late VoiceModelStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('puck-voice-test-');
    // A store that answers 500 to everything, so every test starts wired and
    // the ones about the catalogue still have something to dispose.
    store = VoiceModelStore(
      root: root,
      client: MockClient((http.Request request) async {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
      }),
    );
  });

  tearDown(() {
    store.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A client that answers every request with [body] and the given status.
  MockClient clientReturning(
    List<int> body, {
    int status = 200,
    bool includeLength = true,
  }) {
    return MockClient((http.Request request) async {
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        status,
        contentLength: includeLength ? body.length : null,
      );
    });
  }

  group('single-file model', () {
    test('downloads, verifies and installs with nothing left behind', () async {
      store = VoiceModelStore(
        root: root,
        client: clientReturning(utf8.encode('VAD-BYTES!!')),
      );

      final ModelInstallResult result = await store.install(_singleFileModel);

      expect(result.ok, isTrue, reason: result.message);
      expect(await store.isInstalled(_singleFileModel), isTrue);

      final File file = File(
        '${store.directoryOf(_singleFileModel)}/silero_vad.onnx',
      );
      expect(file.readAsStringSync(), 'VAD-BYTES!!');

      // The scratch artefacts are the thing that accumulates on a phone.
      final List<String> names = root
          .listSync()
          .map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(names, <String>['single-file']);
    });

    test('a truncated body is a failure, not a smaller model', () async {
      store = VoiceModelStore(
        root: root,
        // The model declares 11 bytes; the server sends 3.
        client: clientReturning(utf8.encode('VAD')),
      );

      final ModelInstallResult result = await store.install(_singleFileModel);

      expect(result.ok, isFalse);
      expect(result.message, startsWith('size'));
      expect(await store.isInstalled(_singleFileModel), isFalse);
      expect(Directory(store.directoryOf(_singleFileModel)).existsSync(), isFalse);
    });

    test('an HTTP error is reported with its status', () async {
      store = VoiceModelStore(
        root: root,
        client: clientReturning(<int>[], status: 404),
      );

      final ModelInstallResult result = await store.install(_singleFileModel);

      expect(result.ok, isFalse);
      expect(result.message, 'http 404');
    });

    test('an empty file on disk does not count as installed', () async {
      store = VoiceModelStore(root: root, client: clientReturning(<int>[]));
      final Directory dir = Directory(store.directoryOf(_singleFileModel))
        ..createSync(recursive: true);
      File('${dir.path}/silero_vad.onnx').writeAsBytesSync(<int>[]);

      expect(await store.isInstalled(_singleFileModel), isFalse);
      expect(await store.missingFiles(_singleFileModel),
          <String>['silero_vad.onnx']);
    });
  });

  group('archive model', () {
    test('extracts only the declared files, without the root directory', () async {
      store = VoiceModelStore(root: root, client: clientReturning(_tarball()));

      final ModelInstallResult result = await store.install(_archiveModel);

      expect(result.ok, isTrue, reason: result.message);
      expect(await store.isInstalled(_archiveModel), isTrue);

      final Directory dir = Directory(store.directoryOf(_archiveModel));
      final Set<String> names = dir
          .listSync()
          .map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last)
          .toSet();

      // The README and the test WAVs in the release are not installed: writing
      // them triples the install for nothing.
      expect(names, <String>{'encoder_model.ort', 'tokens.txt'});
      expect(
        File('${dir.path}/encoder_model.ort').readAsStringSync(),
        'ENCODER-BYTES',
      );
    });

    test('progress ends at complete, and reports extraction', () async {
      store = VoiceModelStore(root: root, client: clientReturning(_tarball()));

      final List<ModelInstallProgress> seen = <ModelInstallProgress>[];
      await store.install(
        _archiveModel,
        onProgress: seen.add,
      );

      expect(seen, isNotEmpty);
      expect(seen.last.fraction, 1.0);
      expect(seen.any((ModelInstallProgress p) => p.extracting), isTrue);
      // Bytes arrive before anything is unpacked.
      expect(seen.first.extracting, isFalse);
    });

    test('a body that is not bzip2 fails cleanly and leaves nothing', () async {
      store = VoiceModelStore(
        root: root,
        client: clientReturning(List<int>.filled(285, 7)),
      );

      final ModelInstallResult result = await store.install(_archiveModel);

      expect(result.ok, isFalse);
      expect(result.message, startsWith('extract'));
      expect(Directory(store.directoryOf(_archiveModel)).existsSync(), isFalse);
      final List<String> names = root
          .listSync()
          .map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(names, isEmpty);
    });

    test('an archive missing a declared file is rejected', () async {
      const VoiceModel wantsTooMuch = VoiceModel(
        id: 'too-much',
        name: 'Too much',
        kind: VoiceModelKind.asr,
        license: 'MIT',
        licenseUrl: 'https://example.invalid/licence',
        archiveUrl: 'https://example.invalid/model.tar.bz2',
        archiveBytes: 285,
        rootDir: 'model-x',
        files: <String>['encoder_model.ort', 'joiner.onnx'],
      );
      store = VoiceModelStore(root: root, client: clientReturning(_tarball()));

      final ModelInstallResult result = await store.install(wantsTooMuch);

      expect(result.ok, isFalse);
      expect(result.message, 'missing joiner.onnx');
      expect(await store.isInstalled(wantsTooMuch), isFalse);
    });
  });

  group('cancellation', () {
    test('a cancel before the first chunk installs nothing', () async {
      store = VoiceModelStore(root: root, client: clientReturning(_tarball()));
      final ModelInstallCancel token = ModelInstallCancel()..cancel();

      final ModelInstallResult result =
          await store.install(_archiveModel, cancel: token);

      expect(result.ok, isFalse);
      expect(result.message, 'cancelled');
      expect(await store.isInstalled(_archiveModel), isFalse);
    });
  });

  group('housekeeping', () {
    test('remove deletes the model and reports zero bytes', () async {
      store = VoiceModelStore(
        root: root,
        client: clientReturning(utf8.encode('VAD-BYTES!!')),
      );
      await store.install(_singleFileModel);
      expect(await store.installedBytes(_singleFileModel), 11);

      await store.remove(_singleFileModel);

      expect(await store.isInstalled(_singleFileModel), isFalse);
      expect(await store.installedBytes(_singleFileModel), 0);
    });

    test('installedBytes counts every file, not just the declared ones', () async {
      store = VoiceModelStore(root: root, client: clientReturning(_tarball()));
      await store.install(_archiveModel);
      // "ENCODER-BYTES" + "a b c\n"
      expect(await store.installedBytes(_archiveModel), 13 + 6);
    });

    test('the catalogue refuses to advertise a 0 MB download', () {
      // Silero VAD is 0.64 MB. Rounding it to "0 MB" on the button would be a
      // lie in the other direction.
      expect(VoiceModels.sileroVad.totalMegabytes, 1);
      expect(VoiceModels.sileroVad.totalBytes, 643854);
      expect(VoiceModels.sileroVad.isArchive, isFalse);
      expect(VoiceModels.moonshineTinyEn.totalMegabytes, 30);
    });

    test('what a fresh install needs is only VAD plus one recogniser', () {
      expect(
        VoiceModels.requiredForCommands.map((VoiceModel m) => m.id).toList(),
        <String>['silero-vad', 'moonshine-tiny-en'],
      );
      // The optional voice is download-only, never required.
      expect(
        VoiceModels.requiredForCommands
            .where((VoiceModel m) => m.kind == VoiceModelKind.tts),
        isEmpty,
      );
    });
  });
}
