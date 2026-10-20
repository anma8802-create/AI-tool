# Storyboard AI update server

This repository hosts the public update feed and release packages for Storyboard AI.

## Publish a version

1. Build a clean package named `Storyboard_AI_Studio_Pro_vX.Y.Z.zip`.
2. Create a GitHub Release with a stable tag such as `v1.3.1`.
3. Attach the matching ZIP asset and publish the release.
4. The `Publish update feed` workflow validates the tag and asset, calculates the ZIP size and SHA-256, writes `latest.json` to the default branch, and attaches the same manifest to the release.

The app checks:

- `https://raw.githubusercontent.com/anma8802-create/AI-tool/main/latest.json`
- Fallback: the `latest.json` asset on the latest GitHub Release

The manifest points to the ZIP on the latest release. The updater verifies its SHA-256 before installing and preserves user data.
