import 'package:objectbox/objectbox.dart';

/// How many numbers an embedding has.
///
/// Fixed at build time: [HnswIndex] takes `dimensions` as a compile-time
/// constant, so the index cannot be rebuilt for a model of another size at
/// runtime. The catalog therefore offers only 384-dimension embedding models
/// — bge-small, all-MiniLM-L6, e5-small all produce this — and switching
/// between them costs a re-index, not a rebuild of the app.
const int kEmbeddingDimensions = 384;

/// One passage of a document, with the vector it was encoded to.
///
/// The text is stored beside the vector rather than looked back up in the
/// source file: retrieval has to work after the picked file has been moved or
/// deleted, which on a phone is routine.
@Entity()
class DocumentChunk {
  DocumentChunk({
    this.id = 0,
    required this.docId,
    required this.ordinal,
    required this.text,
    required this.embedding,
  });

  @Id()
  int id;

  /// Which document this came from, matching [IngestedDocument.docId].
  @Index()
  String docId;

  /// Position in the document, counting from zero. Shown to the model so it
  /// can say roughly where in the document an answer came from.
  int ordinal;

  String text;

  /// Cosine distance, because embedding models are trained for cosine
  /// similarity; the default squared Euclidean would rank by vector length as
  /// much as by meaning.
  @HnswIndex(
    dimensions: kEmbeddingDimensions,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double> embedding;
}

/// One document that has been read, chunked and encoded.
@Entity()
class IngestedDocument {
  IngestedDocument({
    this.id = 0,
    required this.docId,
    required this.title,
    required this.sourcePath,
    required this.chunkCount,
    required this.embedModelId,
    required this.ingestedAt,
    this.chunkChars = 0,
  });

  @Id()
  int id;

  /// Derived from the file's path, so picking the same file twice is
  /// recognised as the same document and costs no second encoding.
  @Index()
  String docId;

  /// The file's name, which is what the model quotes as the source.
  String title;

  String sourcePath;

  int chunkCount;

  /// Which embedding model encoded it. A different model produces vectors
  /// that are not comparable with these, so changing model forces a re-index
  /// rather than silently returning nonsense.
  String embedModelId;

  /// How long each passage was cut to. Recorded for the same reason
  /// [embedModelId] is: changing it makes these chunks the wrong ones, so the
  /// document has to be read and encoded again rather than answered from
  /// passages of the old size. Zero on a row written before this was stored,
  /// which reads as "unknown" and forces one re-index.
  int chunkChars;

  @Property(type: PropertyType.date)
  DateTime ingestedAt;
}
