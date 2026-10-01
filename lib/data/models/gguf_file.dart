import 'byte_size.dart';

/// One downloadable `.gguf` inside a Hugging Face repository.
///
/// Built from `GET /api/models/{repo}/tree/main`, which is the only endpoint
/// that reports file sizes — the model list does not.
class GgufFile {
  const GgufFile({
    required this.repoId,
    required this.fileName,
    required this.sizeBytes,
  });

  final String repoId;
  final String fileName;
  final int sizeBytes;

  /// Stable across the app: also the id of the model once installed.
  String get id => '$repoId/$fileName';

  /// Where the weights are fetched from.
  String get downloadUrl =>
      'https://huggingface.co/$repoId/resolve/main/$fileName';

  /// `1.10 GB`.
  String get sizeLabel => formatBytes(sizeBytes);

  /// `Q4_K_M · 1.10 GB`, the label on a quant chip.
  String get chipLabel => '$quantization · $sizeLabel';

  /// A file this large will not load on a typical phone.
  ///
  /// There is no portable way to read total device RAM from Flutter, so this is
  /// a flat threshold rather than a real measurement: a 4-bit quant needs
  /// roughly its file size in RAM plus the KV cache, and ~2 GB is already more
  /// than a mid-range device will give one app. Heavy files are still offered —
  /// the chip is just marked — because a tablet or desktop may well cope.
  static const int heavyThresholdBytes = 2 * 1000 * 1000 * 1000;

  bool get isHeavy => sizeBytes >= heavyThresholdBytes;

  /// The quantisation tag, e.g. `Q4_K_M`, `IQ3_XS`, `F16`.
  ///
  /// Hugging Face has no field for this; it only ever appears in the file name.
  /// The last match wins because the tag is conventionally the final segment,
  /// and the result is upper-cased so `…-q8_0.gguf` and `…-Q8_0.gguf` agree.
  String get quantization {
    final stem = fileName.replaceAll(
      RegExp(r'\.gguf$', caseSensitive: false),
      '',
    );
    final matches = _quantPattern.allMatches(stem);
    if (matches.isEmpty) return 'GGUF';
    return matches.last.group(1)?.toUpperCase() ?? 'GGUF';
  }

  static final RegExp _quantPattern = RegExp(
    r'(?:^|[-_.])((?:IQ|Q)\d+(?:_[A-Z0-9]+)*|MXFP4(?:_MOE)?|BF16|FP16|F16|F32)'
    r'(?=[-_.]|$)',
    caseSensitive: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GgufFile && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
