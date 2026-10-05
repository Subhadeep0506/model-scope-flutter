/// Which third-party credential a field holds. Only [huggingFace] is used by
/// this build; the other two are stored for the Agent tab, still unbuilt.
enum ApiKeyKind {
  huggingFace(
    label: 'Hugging Face',
    hint: 'hf_...',
    caption: 'Needed to pull gated GGUF repos',
    storageKey: 'hugging_face_token',
  ),
  firecrawl(
    label: 'Firecrawl',
    hint: 'fc-...',
    caption: 'Web scraping for the price agent',
    storageKey: 'firecrawl_key',
  ),
  tavily(
    label: 'Tavily',
    hint: 'tvly-...',
    caption: 'Web search for research agents',
    storageKey: 'tavily_key',
  );

  const ApiKeyKind({
    required this.label,
    required this.hint,
    required this.caption,
    required this.storageKey,
  });

  final String label;
  final String hint;
  final String caption;

  /// Key under which the secret is stored. Separate from [name] so renaming an
  /// enum value cannot silently orphan a stored credential.
  final String storageKey;

  /// Whether this build can check the key against its service.
  bool get isVerifiable => this == ApiKeyKind.huggingFace;
}

/// The outcome of pressing Verify on one key.
sealed class VerifyState {
  const VerifyState();
}

class VerifyIdle extends VerifyState {
  const VerifyIdle();
}

class VerifyChecking extends VerifyState {
  const VerifyChecking();
}

class VerifyPassed extends VerifyState {
  const VerifyPassed(this.accountName);

  /// The Hugging Face username the token belongs to.
  final String accountName;
}

class VerifyFailed extends VerifyState {
  const VerifyFailed(this.reason);

  final String reason;
}
