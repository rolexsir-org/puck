/// The model catalogue: what Puck can download, how big it is, and what it is
/// licensed under.
///
/// # Why downloads and not assets
///
/// The models are the only large thing in this app, and they are large enough
/// that bundling them would change what Puck *is*: the whole APK is currently
/// a few megabytes per ABI, and the voice engine's smallest useful ASR model is
/// five times that. Bundling also makes the app unusable on a phone with 200 MB
/// free, which is exactly the phone this app is for.
///
/// So: one download, on demand, with the size on the button, over whatever
/// connection the user has. Nothing downloads silently -- [VoiceModelStore]
/// only runs when a person pressed the row.
///
/// # The numbers
///
/// Every [bytes] value below was read from the publishing release's asset list
/// on 2026-11-02 (the `asr-models`, `tts-models` and keyword-spotting releases),
/// not estimated. They are used for two things: telling the user what the
/// download costs, and checking that the bytes that arrived are the bytes that
/// were meant to arrive.
library;

enum VoiceModelKind { vad, asr, tts }

/// A single file inside a model directory, downloaded on its own.
class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.bytes,
  });

  /// File name inside the model directory.
  final String name;
  final String url;
  final int bytes;
}

class VoiceModel {
  const VoiceModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.license,
    required this.licenseUrl,
    required this.files,
    this.archiveUrl = '',
    this.archiveBytes = 0,
    this.rootDir = '',
    this.extraFiles = const <ModelFile>[],
    this.note = '',
  });

  /// Stable id, also the directory name on disk.
  final String id;

  /// What the settings row calls it.
  final String name;
  final VoiceModelKind kind;

  /// Human-readable licence of the model weights, and where it is stated.
  /// Separate from the library's licence: the engine is Apache-2.0 and every
  /// model has its own terms.
  final String license;
  final String licenseUrl;

  /// `.tar.bz2` to download and unpack. Empty for a single-file model.
  final String archiveUrl;
  final int archiveBytes;

  /// Directory inside the archive. The files are lifted out of it, so the model
  /// directory on disk has no redundant nesting.
  final String rootDir;

  /// Files downloaded straight into the model directory: the TTS lexicon,
  /// which is published on its own rather than inside the voice archive, and
  /// every file of a model that has no archive at all (Silero VAD is one
  /// `.onnx` file and is downloaded as itself, not unpacked from a tarball).
  final List<ModelFile> extraFiles;

  /// Paths, relative to the model directory, that must all exist before the
  /// model counts as installed. This is the integrity check that matters: a
  /// truncated download leaves a missing or empty file, and a missing file is
  /// free to detect.
  final List<String> files;

  /// Shown under the model's name. Empty for the plain ones.
  final String note;

  bool get isArchive => archiveUrl.isNotEmpty;

  int get totalBytes => archiveBytes +
      extraFiles.fold<int>(0, (int sum, ModelFile f) => sum + f.bytes);

  /// Rounded, with a floor of one, so a 0.6 MB model never advertises itself
  /// as "0 MB" and never as "1 MB" when it is actually 0.4.
  int get totalMegabytes {
    if (totalBytes <= 0) return 0;
    final int mb = (totalBytes / 1000000).round();
    return mb < 1 ? 1 : mb;
  }
}

abstract final class VoiceModels {
  /// Voice activity detection. Tiny, required, and the reason a command ends
  /// when the person stops talking instead of when a timer expires.
  static const VoiceModel sileroVad = VoiceModel(
    id: 'silero-vad',
    name: 'Silero VAD',
    kind: VoiceModelKind.vad,
    license: 'MIT',
    licenseUrl: 'https://github.com/snakers4/silero-vad/blob/master/LICENSE',
    // Not an archive: the release publishes the graph itself, so it is
    // downloaded as a single file. Routing it through the tarball path would
    // feed an ONNX protobuf to the bzip2 decoder.
    extraFiles: <ModelFile>[
      ModelFile(
        name: 'silero_vad.onnx',
        url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
            'asr-models/silero_vad.onnx',
        bytes: 643854, // measured 2026-11-02
      ),
    ],
    files: <String>['silero_vad.onnx'],
  );

  /// The default recogniser.
  ///
  /// Chosen over Whisper tiny.en (118 MB) and Zipformer (308 MB) because the
  /// commands are short and the model has to answer in well under a second on
  /// a mid-range phone: Moonshine tiny is built for short utterances, and a
  /// quantised copy is 30 MB, which is a download a person will actually
  /// accept. It is English-only, which is the language every command phrase in
  /// this app is written in.
  static const VoiceModel moonshineTinyEn = VoiceModel(
    id: 'moonshine-tiny-en',
    name: 'Moonshine tiny (English)',
    kind: VoiceModelKind.asr,
    license: 'MIT (Moonshine, Useful Sensors)',
    licenseUrl: 'https://github.com/usefulsensors/moonshine/blob/main/LICENSE',
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27.tar.bz2',
    archiveBytes: 29858559, // measured 2026-11-02 (29.9 MB)
    rootDir: 'sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27',
    files: <String>[
      'encoder_model.ort',
      'decoder_model_merged.ort',
      'tokens.txt',
    ],
    note: 'Default',
  );

  /// The larger alternative, kept because Whisper handles accents and longer
  /// sentences better than Moonshine tiny and some people will take the
  /// download.
  static const VoiceModel whisperTinyEn = VoiceModel(
    id: 'whisper-tiny-en',
    name: 'Whisper tiny (English)',
    kind: VoiceModelKind.asr,
    license: 'MIT (Whisper, OpenAI)',
    licenseUrl: 'https://github.com/openai/whisper/blob/main/LICENSE',
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-whisper-tiny.en.tar.bz2',
    archiveBytes: 118071777, // measured 2026-11-02 (118.1 MB)
    rootDir: 'sherpa-onnx-whisper-tiny.en',
    files: <String>[
      'tiny.en-encoder.int8.onnx',
      'tiny.en-decoder.int8.onnx',
      'tiny.en-tokens.txt',
    ],
  );

  /// Optional offline voice for spoken answers.
  ///
  /// Off by default: Android already has a speech engine, it is already
  /// offline on most phones, and it sounds better than a 67 MB VITS model. This
  /// exists for the phone whose engine is missing, silenced, or set to a
  /// language the user does not want to hear. The lexicon file is separate
  /// because it is read through the model's own text frontend instead of the
  /// phonemiser, which keeps the download smaller and needs no extra native
  /// component.
  static const VoiceModel piperAmyLow = VoiceModel(
    id: 'piper-amy-low',
    name: 'Puck voice (English, amy)',
    kind: VoiceModelKind.tts,
    license: 'Piper is MIT; the voice model card states its dataset licence '
        '(verify before redistribution)',
    licenseUrl: 'https://github.com/rhasspy/piper/blob/master/LICENSE.md',
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-amy-low.tar.bz2',
    archiveBytes: 67095344, // measured 2026-11-02 (67.1 MB)
    rootDir: 'vits-piper-en_US-amy-low',
    extraFiles: <ModelFile>[
      ModelFile(
        name: 'lexicon-en-us.txt',
        url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
            'tts-models/lexicon-en-us.txt',
        bytes: 6305773, // measured 2026-11-02 (6.3 MB)
      ),
    ],
    files: <String>['en_US-amy-low.onnx', 'tokens.txt', 'lexicon-en-us.txt'],
    note: 'Only needed if your phone has no speech engine',
  );

  /// Everything the settings screen can offer, in install order.
  static const List<VoiceModel> catalogue = <VoiceModel>[
    sileroVad,
    moonshineTinyEn,
    whisperTinyEn,
    piperAmyLow,
  ];

  /// What "voice commands" actually needs.
  static const List<VoiceModel> requiredForCommands = <VoiceModel>[
    sileroVad,
    moonshineTinyEn,
  ];

  /// The keyword-spotting model Puck does *not* ship yet, recorded here so the
  /// wake-word work starts from a checked fact rather than a guess.
  ///
  /// It is an English Zipformer transducer trained on GigaSpeech, 17.6 MB, and
  /// the engine package exposes it as `KeywordSpotter` with a `keywords.txt`
  /// file of BPE-encoded phrases. See docs/voice.md §5 for why it is not wired
  /// up: a
  /// wake word is a foreground service and an always-on microphone, and that is
  /// a battery and trust decision, not a code one.
  static const String keywordSpotterModelId =
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';
  static const String keywordSpotterUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/'
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2';
  static const int keywordSpotterBytes = 17626723; // measured 2026-11-02
}
