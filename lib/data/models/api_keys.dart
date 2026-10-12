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

  final String storageKey;

  bool get isVerifiable => true;
}

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

  final String summary;
}

class VerifyFailed extends VerifyState {
  const VerifyFailed(this.reason);

  final String reason;
}
