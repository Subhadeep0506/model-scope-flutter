# Model assets

**Nothing goes here any more.** This folder is no longer declared in
`pubspec.yaml` and nothing in the app reads from it.

Models arrive at runtime: **Settings → Models → Add model** browses the Hugging
Face GGUF catalogue, and tapping a quantisation chip downloads it. The weights
land in `nobodywho`'s own cache directory; the app records the absolute path in
`models.json` and loads from there.

That replaces the previous arrangement, where a single 386 MB `.gguf` had to be
placed here by hand and was copied out of the asset bundle on first launch. It
meant the app could only ever run one model, and only after a manual step that
is not part of a normal checkout.

To try the smallest sensible model, search `SmolLM2-360M-Instruct-GGUF` in the
Add model sheet and pick `Q8_0` (~399 MB).

## Gated repositories

Some repos require a Hugging Face account to download. Paste a token into
**Settings → API keys → Hugging Face** and press Verify. The token is held in
the platform keychain (`flutter_secure_storage`), not in the app's JSON files.

## This file

Keep it, so the empty directory survives in the repository and anyone who goes
looking for the old asset path finds this explanation instead.
