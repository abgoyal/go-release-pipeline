# Go Release Pipeline

This repository contains a reusable GitHub Actions workflow for building, signing, packaging, and publishing Go applications. It automates the creation of `.deb`, `.rpm`, and `.apk` packages, hosts them in a self-cleaning repository on GitHub Pages, and cleans up old GitHub Releases.

## Usage

To use this workflow, create a `.github/workflows/release.yml` file in your Go project repository. Look at the associated template/demo repository
for detailed instructions.

### Release on Tag Push

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    uses: abgoyal/go-release-pipeline/.github/workflows/pipeline.yml@main
    with:
      # --- Required ---
      goreleaser-config-path: .goreleaser.yml

      # --- Optional: Toggle package formats ---
      enable-deb: true
      enable-rpm: true
      enable-apk: true

      # --- Optional: Customization ---
      go-version: '1.24'
      # Path to your project's post-install scripts.
      # Required if the corresponding package format is enabled.
      deb-postinstall-path: .github/scripts/postinstall.deb.sh
      rpm-postinstall-path: .github/scripts/postinstall.rpm.sh

    secrets: inherit # Securely passes required secrets
````

### Dry Run on Pull Request

To test changes to your release process, you can run the pipeline in "dry-run" mode on pull requests. This builds and packages everything but does not publish.

```yaml
name: Test Release
on:
  pull_request:

jobs:
  dry-run-release:
    uses: abgoyal/go-release-pipeline/.github/workflows/pipeline.yml@main
    with:
      dry-run: true
      goreleaser-config-path: .goreleaser.yml
      enable-deb: true
      enable-rpm: true
      enable-apk: true
      deb-postinstall-path: .github/scripts/postinstall.deb.sh
      rpm-postinstall-path: .github/scripts/postinstall.rpm.sh
    secrets: inherit
```

### Required Secrets

You must configure the following secrets in your repository for the package formats you enable:

  * `DEB_GPG_PRIVATE_KEY`, `DEB_GPG_PASSPHRASE`
  * `RPM_GPG_PRIVATE_KEY`, `RPM_GPG_PASSPHRASE`
  * `APK_GPG_PRIVATE_KEY`, `APK_GPG_PASSPHRASE`

