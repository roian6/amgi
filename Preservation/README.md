# Preserved Amgi development branches

This branch is a clean source snapshot based on public Amgi `63440c59b08af8b6010923e0656e0ae070a1eee9`. The original physical-device operational log, local homes, credentials, generated builds, and collection/media originals are not published. This is preservation, not a fresh device or build acceptance.

## Watch dependency

The Amgi gitlink intentionally stays at public Anki base `e64c6b1aee3e8d668fb8bbe084beada8e070d985`. Two previously local Anki commits (`02a3f4ab9bbe1d9e4555d8bdadd075f6e1c2c70f`, `b551992648d391558694411fe236c9fd91ff4ec4`) are preserved as an aggregate patch with exact per-file blob identities in `anki-watch-sync.json`. They are not assumed to exist in the upstream Anki remote.

After cloning this feature branch:

```sh
git submodule update --init --recursive
python3 scripts/apply-watch-anki-patch.py
./scripts/build-xcframework.sh
```

The build script also invokes the idempotent patch check before compilation. It refuses unrelated checkout changes. The patch changes only six ordinary Rust source files, and the source-delta application/idempotence was exercised on an isolated sparse checkout. The full iOS/watchOS build and fresh physical acceptance were not rerun for this preservation.

Anki retains its upstream AGPL-3.0 licensing; the patch does not replace the upstream license or notices. Amgi's existing license remains in this fork. The separate review-input feature branch preserves its own source without publishing historical operational notes.
