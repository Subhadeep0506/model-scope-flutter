/// Which third-party credential a field holds. [huggingFace] pulls model
/// weights; the other two back the web tools agents call.
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
    caption: 'Reading web pages for agents',
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
  ///
  /// True for all three: each service has an endpoint that reports on the key
  /// — an account for Hugging Face, a usage figure for the other two — without
  /// spending any of its allowance. The getter stays because a credential
  /// added later may have nowhere free to check it.
  bool get isVerifiable => true;
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
  const VerifyPassed(this.summary);

  /// The whole caption, ready to show: `Verified as octocat`, or a plan and
  /// a credit figure. Each service says something different about a good key,
  /// so the sentence is built where it is known rather than reassembled here.
  final String summary;
}

class VerifyFailed extends VerifyState {
  const VerifyFailed(this.reason);

  final String reason;
}
