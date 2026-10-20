# Storyboard AI update server

This repository hosts the public update feed and release assets for Storyboard AI.

## Client endpoints

- Primary: https://raw.githubusercontent.com/anma8802-create/AI-tool/main/latest.json
- Fallback: https://github.com/anma8802-create/AI-tool/releases/latest/download/latest.json

These public endpoints do not require a GitHub login on client machines. An older installation that uses another feed must be configured once to use these URLs.

## Publish from the primary PC

GitHub CLI on the primary PC publishes the package and manifest. This route does not require GitHub Actions.

1. Build a clean package named `Storyboard_AI_Studio_Pro_vX.Y.Z.zip` and its matching `latest.json`.
2. Check the manifest version, ZIP filename, byte count and SHA-256 against the actual ZIP.
3. Create a draft Release tagged `vX.Y.Z` with GitHub CLI and attach both the ZIP and `latest.json`.
4. Verify that the uploaded ZIP's GitHub SHA-256 digest matches the local file.
5. Publish the Release and mark it as latest.
6. Commit the same `latest.json` to the root of `main`.
7. Verify both public manifest URLs and the package download from a client machine.

The manifest contains `version`, `release_name`, `installer`, `bytes`, `sha256` and `release_notes`. The installer URL is the ZIP asset on the latest Release.

Never publish personal settings, account data or API credentials in release packages.

## Optional Actions workflow

`Publish update feed` can generate and publish the manifest after a stable Release is published. It is currently disabled; the primary-PC publishing procedure above is the active route. Enable the workflow only when GitHub Actions can run for this repository.
