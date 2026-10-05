import 'byte_size.dart';

/// What a `.gguf` in a repository actually is. Only a [model] can answer a
/// prompt; the other two are listed without a download button.
enum GgufFileKind {
  /// Weights. The only kind the app downloads.
  model('Model'),

  /// A vision projector. Holds no weights of its own, but downloading one
  /// gives every installed quant of its repository the ability to read images.
  mmproj('MMProj'),

  /// A LoRA or similar, which has to be applied to a base model.
  adapter('Adapter');

  const GgufFileKind(this.label);

  /// The mono badge at the head of the row.
  final String label;
}

/// One `.gguf` inside a Hugging Face repository. Built from
/// `GET /api/models/{repo}/tree/main`, the only endpoint reporting file sizes.
class GgufFile {
  const GgufFile({
    required this.repoId,
    required this.fileName,
    required this.sizeBytes,
    this.kind = GgufFileKind.model,
  });

  final String repoId;
  final String fileName;
  final int sizeBytes;
  final GgufFileKind kind;

  /// Whether the app can download this file. Adapters are the exception: they
  /// adjust a base model rather than adding to one, and nothing here applies
  /// them.
  bool get isDownloadable => kind != GgufFileKind.adapter;

  /// Whether this file is a vision projector rather than weights.
  bool get isProjector => kind == GgufFileKind.mmproj;

  /// Stable across the app: also the id of the model once installed.
  String get id => '$repoId/$fileName';

  /// Where the weights are fetched from.
  String get downloadUrl =>
      'https://huggingface.co/$repoId/resolve/main/$fileName';

  /// `1.10 GB`.
  String get sizeLabel => formatBytes(sizeBytes);

  /// `Q4_K_M · 1.10 GB`, the label on a quant chip.
  String get chipLabel => '$quantization · $sizeLabel';

  /// A file this large will not load on a typical phone. A flat threshold, not
  /// a measurement — device RAM is not portably readable. Heavy files are still
  /// offered, just marked, because a tablet or desktop may well cope.
  static const int heavyThresholdBytes = 2 * 1000 * 1000 * 1000;

  bool get isHeavy => sizeBytes >= heavyThresholdBytes;

  /// The quantisation tag, e.g. `Q4_K_M`. Hugging Face has no field for it, so
  /// it comes out of the file name; the last match wins because the tag is
  /// conventionally the final segment.
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
